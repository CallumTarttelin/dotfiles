{
  config,
  pkgs,
  ...
}: {
  time.timeZone = "Europe/London";

  # TODO move this to a better place
  environment.variables.FLAKE = "/home/tarttelin/Documents/nixtest/newconfig";

  environment.systemPackages = [
    # Needed for flakes
    pkgs.git
  ];

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

    keep-derivations = true;
    keep-outputs = true;
    substituters = [
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  users.users.root.hashedPasswordFile = config.age.secrets.root.path;

  users.users.tarttelin = {
    isNormalUser = true;
    extraGroups = ["wheel" "libvirtd" "docker" "networkmanager" "podman" "input" "yubikey"];
    shell = pkgs.zsh;
    hashedPasswordFile = config.age.secrets.tarttelin.path;
  };

  age = {
    secrets = {
      root.file = ../secrets/root.age;
      tarttelin.file = ../secrets/tarttelin.age;
    };
    identityPaths = ["/root/.ssh/id_rsa"];
  };

  nixpkgs.config.allowUnfree = true;
}
