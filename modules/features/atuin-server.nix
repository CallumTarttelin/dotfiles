_: {
  flake.nixosModules.atuin-server = {
    config,
    lib,
    ...
  }: {
    options.features.atuin-server.enable = lib.mkEnableOption "Atuin shell history server";

    config = lib.mkIf config.features.atuin-server.enable {
      services.atuin = {
        enable = true;
        openRegistration = true;
        host = "0.0.0.0";
        port = 8888;
      };
    };
  };
}
