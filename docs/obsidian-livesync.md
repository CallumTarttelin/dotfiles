# Obsidian LiveSync on Nixie

Nixie hosts CouchDB for the Self-hosted LiveSync community plugin. Clients keep
ordinary local vaults; CouchDB stores the sync representation. Syncing happens
while the relevant vault is open in Obsidian, so Android does not need a separate
background sync app. Closed vaults do not sync independently.

## Connect a vault

- Server: `https://obsidian.callumtarttelin.com`
- Database: `personal` or `work` (separate, initially empty databases)
- Username: `livesync`
- Retrieve the generated password in your own terminal with
  `ssh root@nixie 'cat /run/agenix/livesync-client'`.

The `livesync` account is a server administrator, as requested for Obsidian's
LiveSync setup. It can inspect server configuration and create additional vault
databases. Both vaults use the same account; their separation is organisational.

1. Back up the existing vault and disable any other sync tool for that vault.
2. Enable Tailscale and install **Self-hosted LiveSync** from Community plugins.
3. On the first device, follow the new-sync setup using the CouchDB details above.
   Use this device's notes to initialise the selected empty remote database.
   The server requirements check can inspect the existing configuration using
   this account; the server is already configured declaratively.
4. Enable end-to-end encryption and store its passphrase in Vaultwarden. This
   passphrase is separate from the CouchDB login password.
5. Enable continuous LiveSync, or startup/event syncing if preferred. Allow the
   initial upload to finish with Obsidian open.
6. Generate a Setup URI from the working first device. Add other devices through
   the existing-sync setup, initially using an empty or separately backed-up
   vault. Protect the Setup URI and its passphrase; it contains credentials.
7. Test a note in both directions. Configure settings/plugin sync separately
   after ordinary notes work, keeping device-specific window layouts local.

Repeat for the other vault when needed. No existing notes are moved by the
server deployment. Additional vaults can use distinct database names in the
plugin. The provisioning service ensures `personal` and `work` exist on boot.

## Access and credentials

CouchDB listens on `127.0.0.1:5984`. Caddy uses the existing wildcard certificate
and permits Tailscale source addresses plus loopback; other source addresses
receive HTTP 403. HTTPS is required by LiveSync on mobile even on a tailnet.
Obsidian's desktop and mobile CORS origins are explicitly allowed.

Both passwords are generated randomly and committed only as age-encrypted files
using the repository's existing recipients. Agenix installs the administrator
INI readable only by CouchDB, and the client JSON readable only by root.
Provisioning uses systemd credentials and does not log either password.

Provisioning grants `livesync` server administration through CouchDB's configuration
API and verifies the role after its authentication cache refreshes. The salted
administrator hash persists in `local.ini`, included in both off-site backups.
Client password changes are applied to both account records when provisioning runs.
CouchDB may persist an administrator password hash in `/var/lib/couchdb/local.ini`;
administrator rotation must also update that persisted admin entry, rather than
only replacing the encrypted INI.

## Monitoring

[Obsidian LiveSync dashboard](https://grafana.callumtarttelin.com/d/obsidian-livesync)
shows service CPU, cgroup memory, tasks, restarts, database storage, HTTPS health,
sample freshness, host available memory, and journal logs.

The existing node exporter reads a textfile updated once per minute. CPU includes
all Erlang children and is expressed as a percentage of one logical core. Memory
includes the whole service cgroup and filesystem cache, so it differs from RSS.
The existing blackbox exporter probes `/_up` every minute and the existing
service-down alert covers this endpoint. Resource samples do not require another
exporter daemon. Journal logs already flow through Alloy into Loki.

Erlang scheduler busy-waiting is disabled for this intermittent workload. The
default runtime spent substantial CPU spinning while the empty database was idle.
The runtime uses two Erlang schedulers, sufficient for a few vaults, to reduce
per-scheduler statistics and background housekeeping. Revisit this setting if
sync throughput becomes a bottleneck.
An empty-service quiet sample measured about 1.9% of one core over 90 seconds,
down from about 2.3% with twenty schedulers and busy-waiting already disabled.
Profiling identified internal histogram cleanup as the main remaining background
work. Increasing the statistics interval did not materially reduce CPU and was
reverted; this configuration retains the default interval.
There is no arbitrary memory cap; use the dashboard to assess actual vault usage.

Useful checks on Nixie:

```sh
systemctl status couchdb couchdb-livesync-init
systemctl show couchdb -p MemoryCurrent -p CPUUsageNSec -p TasksCurrent -p NRestarts
journalctl -u couchdb -u couchdb-livesync-init
curl https://obsidian.callumtarttelin.com/_up
systemctl start couchdb-resource-metrics.service
```

## Backups and recovery

Both existing nightly Restic jobs include `/var/lib/couchdb`, containing database
files, indexes, the Erlang cookie, and mutable `local.ini`. CouchDB's append-only
files support online file backups. An index copied later than its database may
require rebuilding on recovery. Configuration is otherwise reproduced from Nix
and the encrypted administrator secret. Client passwords remain in the encrypted
repository secret. Retain the vault encryption passphrase separately.

On a recovery host with this configuration, stop CouchDB, restore
`/var/lib/couchdb` from the selected Restic snapshot, restore ownership to
`couchdb:couchdb` and private directory permissions, then start CouchDB and its
provisioning service. Verify database access before reconnecting clients. Keep
separate Markdown vault backups as an app-independent recovery path.

Validation includes a full Nixie system build, isolated CouchDB provisioning,
read/write and access-control checks, repeat provisioning without changing vault
documents or user revisions, client password rotation, and restoring an online
file copy into a separate instance. Live checks cover TLS, sync-account access,
anonymous denial, CORS, non-Tailscale denial, dashboard provisioning, and metric
ingestion. Full Obsidian desktop/Android sync remains a client setup check.
The later server administrator change was verified using the existing client
credentials against the administrator configuration API over HTTPS.

Sources: [LiveSync setup](https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/quick_setup.md),
[LiveSync settings](https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/settings.md),
[CouchDB backups](https://docs.couchdb.org/en/stable/maintenance/backups.html).
