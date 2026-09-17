# Forgejo backups

Forgejo's built-in nightly archive contains repositories, configuration, application data, and an SQL dump. The September 2026 audit found that its generated SQL creates some foreign keys before the referenced tables exist. Importing that SQL directly into an empty PostgreSQL database failed; the restic archive itself was readable.

The supplementary `services.postgresqlBackup` job uses native `pg_dump --clean --if-exists forgejo`. PostgreSQL emits the schema, data, and constraints in a restorable order. The built-in archive remains enabled for the other Forgejo files.

The native job runs at midnight, matching the existing archive schedule, and stages its files at:

- `/var/backup/nixie/forgejo-dump/postgresql/forgejo.sql`
- `/var/backup/nixie/forgejo-dump/postgresql/forgejo.prev.sql`

That directory is already inside both off-site backup paths. PostgreSQL owns the directory and the dump files are private; root's restic jobs can read them. Restic compresses the uncompressed SQL. The NixOS module keeps the previous dump and writes the new one through an in-progress file.

After applying the configuration on nixie, run `sudo systemctl start postgresqlBackup-forgejo.service` to produce the first native dump immediately. Otherwise the timer runs at midnight. The next successful S3 and BorgBase jobs include the staged dump. To refresh the fixed monitoring immediately, run `sudo systemctl start restic-snapshot-check.service`.

For recovery, use the native SQL with an empty PostgreSQL database and the Forgejo database role created by the same NixOS configuration. On the recovery host, import it using `psql` with `ON_ERROR_STOP=1`; the dump's cleanup statements replace objects in the target database. Recover repositories, configuration, and other files from the matching Forgejo archive. Do not substitute the archive's built-in SQL for this native dump. The two jobs are separate point-in-time captures, not an application-wide atomic snapshot.

Validation: the exact native dump command was run against nixie, then imported with `ON_ERROR_STOP=1` into an isolated PostgreSQL 15 instance using a private Unix socket and no TCP listener. All 130 tables and 22 foreign keys restored successfully. The temporary instance and dump were removed afterward; production data was not modified. Full application startup/login was not tested.
