_: {
  services.borgbackup.jobs."tarttelin-nixshark" = {
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
    repo = "ssh://va49i77c@va49i77c.repo.borgbase.com/./repo";
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /root/borgbackup/passphrase";
    };
    environment.BORG_RSH = "ssh -i /home/tarttelin/.ssh/borg_key";
    compression = "zstd";
    startAt = "daily";
  };
}
