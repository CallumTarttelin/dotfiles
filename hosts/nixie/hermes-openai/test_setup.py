"""Run with the pinned Hermes Python and the Nix-generated settings JSON."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / ".hermes"
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.root), HERMES_HOME=str(self.home),
                        HERMES_MANAGED="true", OPENAI_API_KEY="private-test-key")
        for name, content in {
            "config.yaml": '{"model":{"default":"private-model"}}',
            ".env": "OPENAI_API_KEY=private-test-key\n",
            "memories/MEMORY.md": "private memory",
            "workspace/private.txt": "private workspace",
            "sessions/private.json": "private session",
            "skills/gws-gmail/SKILL.md": "---\nname: gws-gmail\ndescription: Private Gmail\n---\nPrivate skill\n",
        }.items():
            path = self.home / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.credentials = self.root / "credentials.env"
        self.credentials.write_text("NIXIE_OPENAI_API_KEY=openai-test-key\n")
        self.profile = self.home / "profiles/openai"

    def run_setup(self):
        return subprocess.run([
            sys.executable, str(Path(__file__).with_name("setup.py")),
            "--settings", str(SETTINGS), "--credentials", str(self.credentials),
            "--policy", str(Path(__file__).with_name("SOUL.md")),
        ], env=self.env, capture_output=True, text=True)

    def test_separate_state_routing_and_idempotent_rebuild(self):
        originals = {p: p.read_bytes() for p in self.home.rglob("*") if p.is_file()}
        first = self.run_setup()
        self.assertEqual(first.returncode, 0, first.stderr)
        for path, content in originals.items():
            self.assertEqual(path.read_bytes(), content)
        for directory in ["memories", "sessions", "workspace", "skills"]:
            self.assertEqual(list((self.profile / directory).iterdir()), [])
        self.assertEqual((self.profile / ".env").read_bytes(), self.credentials.read_bytes())
        config = json.loads((self.profile / "config.yaml").read_text())
        self.assertEqual(config["terminal"]["cwd"], str(self.profile / "workspace"))
        (self.profile / "memories/MEMORY.md").write_text("public memory")
        (self.profile / "workspace/work.txt").write_text("work")
        self.assertEqual(self.run_setup().returncode, 0)
        self.assertEqual((self.profile / "memories/MEMORY.md").read_text(), "public memory")
        self.assertEqual((self.profile / "workspace/work.txt").read_text(), "work")
        for name in [".env", "config.yaml", "SOUL.md"]:
            self.assertEqual((self.profile / name).stat().st_mode & 0o777, 0o600)
        check = subprocess.run([sys.executable, "-c", '''
import json,os
from pathlib import Path
from hermes_cli.env_loader import load_hermes_dotenv
load_hermes_dotenv()
from hermes_cli.config import load_config
from hermes_cli.runtime_provider import resolve_runtime_provider
from tools.memory_tool import get_memory_dir
from hermes_state import _default_db_path
cfg=load_config()
runtime=resolve_runtime_provider(requested=cfg['model']['provider'],target_model=cfg['model']['default'])
assert runtime['api_key']=='openai-test-key'
assert runtime['base_url']=='http://127.0.0.1:8090/openai/v1'
assert runtime['api_mode']=='codex_responses'
assert cfg['model']['default']=='gpt-6.1-sol'
assert get_memory_dir()==Path(os.environ['HERMES_HOME'])/'memories'
assert _default_db_path()==Path(os.environ['HERMES_HOME'])/'state.db'
from tools.skills_tool import find_all_skills
assert 'gws-gmail' not in {s['name'] for s in find_all_skills()}
from hermes_cli.profiles import list_profiles
assert {'default','openai'} <= {p.name for p in list_profiles(lazy_skill_count=True)}
'''], env=dict(self.env, HERMES_HOME=str(self.profile)), capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)

    def test_existing_unmanaged_profile_is_untouched(self):
        self.profile.mkdir(parents=True)
        config = self.profile / "config.yaml"
        config.write_text("user configuration")
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to overwrite", result.stderr)
        self.assertEqual(config.read_text(), "user configuration")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    SETTINGS = args.settings
    unittest.main(argv=[sys.argv[0], *remaining])
