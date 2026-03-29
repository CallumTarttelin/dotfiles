{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.build-tools = pkgs.buildEnv {
      name = "build-tools";
      paths = with pkgs; [gcc gnumake protobuf protobufc openssl zig];
    };
  };

  flake.nixosModules.build-tools = {config, lib, pkgs, ...}: {
    options.bundles.build-tools.enable = lib.mkEnableOption "build tools (gcc, make, protobuf, zig)";
    config = lib.mkIf config.bundles.build-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.build-tools
      ];
    };
  };
}
