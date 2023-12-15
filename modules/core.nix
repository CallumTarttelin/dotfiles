{
  config,
  pkgs,
  self,
  inputs,
  lib,
  ...
}: {
  time.timeZone = "Europe/London";

  # Probably not great but oh well
  security.sudo.wheelNeedsPassword = false;

  # TODO move this to a better place
  environment.variables.FLAKE = "/home/tarttelin/Documents/nixtest/newconfig";

  environment.systemPackages = [
    # Needed for flakes
    pkgs.git
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  nix.settings = {
    trusted-users = ["root" "@wheel"];

    auto-optimize-store = true;
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

  nixpkgs.config.allowUnfree = true;
}
