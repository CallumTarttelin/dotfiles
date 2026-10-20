{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "backup-mount" ''
      set -ea
      source ${config.age.secrets.restic-nixshark.path}
      mkdir -p /mnt/backup
      exec ${pkgs.restic}/bin/restic -r sftp:nixie:/var/backup/restic/nixshark mount --allow-other /mnt/backup
    '')
  ];

  services.restic.backups.documents = {
    environmentFile = config.age.secrets.restic-nixshark.path;
    repository = "sftp:nixie:/var/backup/restic/nixshark";
    paths = [
      "/home/tarttelin/Documents"
      # The active LiveSync vault lives outside Documents. Back up its parent
      # so future vaults here also have ordinary-file recovery copies.
      "/home/tarttelin/sync/Obsidian"
    ];
    exclude = [
      "**/target"
      "**/build"
      "**/venv"
      "**/node_modules"
      "**/.gradle"
      "**/dist"
      "**/__pycache__"
    ];
    extraBackupArgs = [
      "--compression max"
    ];
    timerConfig = {
      OnCalendar = "*-*-* 00/6:00:00"; # every 6 hours
      Persistent = true; # run on boot if missed while off
    };
    initialize = true;
  };
}
