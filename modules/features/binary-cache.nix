_: {
  flake.nixosModules.binary-cache = {
    config,
    lib,
    ...
  }: {
    options.features.binary-cache.enable = lib.mkEnableOption "binary cache (harmonia)";

    config = lib.mkIf config.features.binary-cache.enable {
      services.harmonia.cache = {
        enable = true;
        signKeyPaths = [config.age.secrets.cache-key.path];
        settings = {
          bind = "[::]:5000";
          priority = 30;
        };
      };

      # Auto-sign all store paths built on this host
      nix.settings.secret-key-files = [config.age.secrets.cache-key.path];
    };
  };
}
