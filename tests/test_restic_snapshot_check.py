"""Exercise monitoring failures and credential isolation without real secrets."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'modules/features/restic-snapshot-check.sh'


class SnapshotCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.metrics = self.root / 'metrics'
        self.metrics.mkdir()
        restic = self.root / 'restic'
        restic.write_text('''#!/usr/bin/env python3
import json, os, sys
assert '--no-cache' in sys.argv
repo = os.environ['RESTIC_REPOSITORY']
if repo == 'fail':
    print('sensitive backend details', file=sys.stderr)
    sys.exit(1)
if repo == 'empty':
    print('[]')
    sys.exit(0)
if repo == 'bad-date':
    print('[{"time": "not-a-date"}]')
    sys.exit(0)
if repo == '/onsite/client':
    assert os.environ['RESTIC_PASSWORD'] == 'client-password'
    assert 'AWS_ACCESS_KEY_ID' not in os.environ
print(json.dumps([
    {'time': '2026-03-30T01:00:00+01:00'},
    {'time': '2026-09-17T00:30:00+02:00'},
    {'time': '2026-09-16T23:00:00Z'},
]))
''')
        restic.chmod(0o755)
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith(('RESTIC_', 'AWS_')) or key in ('HOME', 'XDG_CACHE_HOME'):
                del self.env[key]
        self.env['PATH'] = str(self.root) + os.pathsep + os.environ['PATH']

    def credential(self, name, contents):
        p = self.root / name
        p.write_text(contents)
        return str(p)

    def run_check(self, *args):
        return subprocess.run(['bash', str(SCRIPT), str(self.metrics), *args],
                              env=self.env, capture_output=True, text=True)

    def metric(self, repo, name):
        text = (self.metrics / f'restic_{repo}.prom').read_text()
        prefix = f'{name}{{repo="{repo}"}} '
        return int(next(line[len(prefix):] for line in text.splitlines()
                        if line.startswith(prefix)))

    def test_newest_instant_across_groups_and_isolated_client_environment(self):
        offsite = self.credential('offsite', 'RESTIC_REPOSITORY=offsite\nAWS_ACCESS_KEY_ID=fake\n')
        client = self.credential('client', 'RESTIC_PASSWORD=client-password\n')
        result = self.run_check('offsite', offsite, '', 'client', client, '/onsite/client')
        self.assertEqual(result.returncode, 0, result.stderr)
        for repo in ('offsite', 'client'):
            # Chronologically newest, despite the next-day string in another timezone.
            self.assertEqual(self.metric(repo, 'restic_last_snapshot_timestamp_seconds'), 1789599600)
            self.assertEqual(self.metric(repo, 'restic_snapshot_check_success'), 1)
            self.assertGreater(self.metric(repo, 'restic_snapshot_check_timestamp_seconds'), 0)
            self.assertEqual((self.metrics / f'restic_{repo}.prom').stat().st_mode & 0o777, 0o644)
        self.assertEqual(len(list(self.metrics.iterdir())), 2)

    def test_failure_replaces_stale_success_and_does_not_skip_later_repositories(self):
        for bad in ('fail', 'empty', 'bad-date', 'missing-file'):
            with self.subTest(bad=bad):
                (self.metrics / 'restic_bad.prom').write_text('stale success')
                credentials = str(self.root / 'absent') if bad == 'missing-file' else self.credential('bad', f'RESTIC_REPOSITORY={bad}\n')
                good = self.credential('good', 'RESTIC_REPOSITORY=good\n')
                result = self.run_check('bad', credentials, '', 'good', good, '')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.metric('bad', 'restic_snapshot_check_success'), 0)
                self.assertEqual(self.metric('bad', 'restic_last_snapshot_timestamp_seconds'), 0)
                self.assertEqual(self.metric('good', 'restic_snapshot_check_success'), 1)
                self.assertNotIn('sensitive backend details', result.stderr)
                self.assertEqual(len(list(self.metrics.iterdir())), 2)

    def test_cannot_report_success_when_metrics_cannot_be_written(self):
        self.metrics.rmdir()
        good = self.credential('good', 'RESTIC_REPOSITORY=good\n')
        result = self.run_check('good', good, '')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
