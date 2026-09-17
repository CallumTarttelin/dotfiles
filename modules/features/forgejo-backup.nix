_: {
  flake.nixosModules.forgejo-backup = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.forgejo;
  in {
    # Keep the application archive for repositories/configuration, but use
    # PostgreSQL's native dump for correctly ordered schema and foreign keys.
    config = lib.mkIf (cfg.enable && cfg.dump.enable && cfg.database.type == "postgres") {
      services.postgresqlBackup = {
        enable = true;
        databases = [cfg.database.name];
        location = "${cfg.dump.backupDir}/postgresql";
        startAt = cfg.dump.interval;
        compression = "none"; # restic compresses the staged SQL
        pgdumpOptions = "--clean --if-exists";
      };
    };
  };
}
