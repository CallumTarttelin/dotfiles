_: {
  flake.nixosModules.igloo-client = {
    config,
    inputs,
    lib,
    pkgs,
    ...
  }: let
    localRunner = config.networking.hostName == "nixie";
    package = inputs.igloo.packages.${pkgs.stdenv.hostPlatform.system}.default;
    client = pkgs.callPackage ../../pkgs/igloo-client {
      igloo = package;
      tokenFile = config.age.secrets.igloo-api.path;
      endpoint =
        if localRunner
        then "http://127.0.0.1:7890"
        else "https://igloo.callumtarttelin.com";
      jumpHost =
        if localRunner
        then null
        else "tarttelin@nixie";
    };
  in {
    age.secrets.igloo-api = {
      file = ../../secrets/igloo-api.age;
      owner = "tarttelin";
      mode = "0400";
    };
    # Prefer the configured client over the runner module's unwrapped executable.
    environment.systemPackages = [(lib.hiPrio client)];
    system.build.iglooClient = client;
  };
}
