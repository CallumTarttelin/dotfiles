_: {
  flake.nixosModules.core = {
    config,
    inputs,
    lib,
    pkgs,
    ...
  }: {
    time.timeZone = "Europe/London";

    # Pin nixpkgs for `nix shell`, `nix run`, `nix-shell` to match flake.lock
    nix.registry.nixpkgs.flake = inputs.nixpkgs;
    nix.nixPath = ["nixpkgs=${inputs.nixpkgs}"];

    environment.etc."fuse.conf".text = "user_allow_other";
    services.openssh.generateHostKeys = true;
    programs.ssh.knownHosts = {
      nixie = {
        hostNames = ["nixie" "nixie.oryx-harmonic.ts.net"];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIE+IF0D7WJNCdXYrwFchwu+KxzgHhXZJcNVDqdglZ47";
      };
      nixshark = {
        hostNames = ["nixshark" "nixshark.oryx-harmonic.ts.net"];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKntjin/g45e5lK8LAUh+ArjnaT8uw+qw+XMPKElh9c6";
      };
      nixwork = {
        hostNames = ["nixwork" "nixwork.oryx-harmonic.ts.net"];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGPKLf6KmW7jCGvzd2NL1dWUW77CIkBaShERbC5QITZ5";
      };
    };

    home-manager.backupFileExtension = "BACKUP";

    environment.systemPackages = with pkgs; [
      git
      gh
      neovim
      bubblewrap
    ];

    programs.nh = {
      enable = true;
      clean = {
        enable = true;
        extraArgs = "--keep 5 --keep-since 7d";
      };
      flake = "/home/tarttelin/Documents/dotfiles";
    };

    environment.pathsToLink = ["/share/zsh"];
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };

    nix.settings = {
      trusted-users = ["root" "@wheel"];
      builders-use-substitutes = true;
      experimental-features = ["nix-command" "flakes"];
      accept-flake-config = true;
      keep-derivations = true;
      keep-outputs = true;
      substituters =
        lib.optional (!config.features.binary-cache.enable) "https://nix-cache.callumtarttelin.com"
        ++ [
          "https://nix-community.cachix.org"
          "https://cache.numtide.com"
          "https://noctalia.cachix.org"
        ];
      trusted-public-keys = [
        "nix-cache.callumtarttelin.com-1:X6SDDEhhlhzWBWoTxK5z/8ggz68nG7sKsWi1si9F4P4="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      ];
    };

    users.users.root.hashedPasswordFile = config.age.secrets.root.path;

    users.users.tarttelin = {
      isNormalUser = true;
      extraGroups = ["wheel" "libvirtd" "docker" "networkmanager" "podman" "input" "yubikey" "adbusers"];
      shell = lib.mkDefault pkgs.zsh;
      hashedPasswordFile = config.age.secrets.tarttelin.path;
    };

    age = {
      secrets = {
        root.file = ../../secrets/root.age;
        tarttelin.file = ../../secrets/tarttelin.age;
        borgpass = {
          file = ../../secrets/borgpass.age;
          path = "/root/borgbackup/passphrase";
        };
        borgrepo.file = ../../secrets/borgrepo.age;
        forgejo-runner.file = ../../secrets/forgejo-runner.age;
        forgejo-runner-native.file = ../../secrets/forgejo-runner-native.age;
        vaultwarden.file = ../../secrets/vaultwarden.age;
        cloudflare.file = ../../secrets/cloudflare.age;
        k8s-minio.file = ../../secrets/k8s-minio.age;
        k8s-grafana.file = ../../secrets/k8s-grafana.age;
        cache-key.file = ../../secrets/cache-key.age;
        restic-s3.file = ../../secrets/restic-s3.age;
        ses-smtp-addr.file = ../../secrets/ses-smtp-addr.age;
        ses-smtp-port.file = ../../secrets/ses-smtp-port.age;
        ses-smtp-user.file = ../../secrets/ses-smtp-user.age;
        ses-smtp-password.file = ../../secrets/ses-smtp-password.age;
        restic-borgbase.file = ../../secrets/restic-borgbase.age;
        restic-nixshark.file = ../../secrets/restic-nixshark.age;
        restic-nixwork.file = ../../secrets/restic-nixwork.age;
      };
      identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/home/tarttelin/.ssh/id_nixshark"
        "/home/tarttelin/.ssh/id_nixie"
        "/home/tarttelin/.ssh/id_nixwork"
      ];
    };

    nixpkgs.config.allowUnfree = true;
  };
}
