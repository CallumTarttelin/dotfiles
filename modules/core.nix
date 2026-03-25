{
  config,
  inputs,
  pkgs,
  home-manager,
  ...
}: {
  time.timeZone = "Europe/London";

  # Pin nixpkgs for `nix shell`, `nix run`, `nix-shell` to match flake.lock
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = ["nixpkgs=${inputs.nixpkgs}"];

  home-manager.backupFileExtension = "BACKUP";

  environment.systemPackages = with pkgs; [
    # Needed for flakes
    git
    gh
    neovim
    bubblewrap
  ];

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 3d";
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
    substituters = [
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  users.users.root.hashedPasswordFile = config.age.secrets.root.path;

  users.users.tarttelin = {
    isNormalUser = true;
    extraGroups = ["wheel" "libvirtd" "docker" "networkmanager" "podman" "input" "yubikey" "adbusers"];
    shell = pkgs.zsh;
    hashedPasswordFile = config.age.secrets.tarttelin.path;
  };

  age = {
    secrets = {
      root.file = ../secrets/root.age;
      tarttelin.file = ../secrets/tarttelin.age;
      borgpass = {
        file = ../secrets/borgpass.age;
        path = "/root/borgbackup/passphrase";
      };
      borgrepo.file = ../secrets/borgrepo.age;
      forgejo-runner.file = ../secrets/forgejo-runner.age;
      yubi.file = ../secrets/yubi.age;
      cloudflare.file = ../secrets/cloudflare.age;

      k8s-minio.file = ../secrets/k8s-minio.age;
      k8s-grafana.file = ../secrets/k8s-grafana.age;
    };
    identityPaths = ["/root/.ssh/id_rsa" "/home/tarttelin/.ssh/id_nixshark" "/home/tarttelin/.ssh/id_nixie" "/home/tarttelin/.ssh/id_nixwork"];
  };

  nixpkgs.config.allowUnfree = true;
}
