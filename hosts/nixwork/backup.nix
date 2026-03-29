{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "backup-mount" ''
      set -ea
      source ${config.age.secrets.restic-nixwork.path}
      mkdir -p /mnt/backup
      exec ${pkgs.restic}/bin/restic -r sftp:nixie:/var/backup/restic/nixwork mount --allow-other /mnt/backup
    '')
  ];

  services.restic.backups.documents = {
    environmentFile = config.age.secrets.restic-nixwork.path;
    repository = "sftp:nixie:/var/backup/restic/nixwork";
    paths = [
      "/home/tarttelin/Documents"
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
