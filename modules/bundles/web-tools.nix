{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.web-tools = pkgs.buildEnv {
      name = "web-tools";
      paths = with pkgs; [nodejs_24 pnpm deno bun];
    };
  };

  flake.nixosModules.web-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.web-tools.enable = lib.mkEnableOption "web development tools (node, pnpm, deno, bun)";
    config = lib.mkIf config.bundles.web-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.web-tools
      ];
    };
  };
}
