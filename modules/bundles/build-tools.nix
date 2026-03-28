{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.build-tools = pkgs.buildEnv {
      name = "build-tools";
      paths = with pkgs; [gcc gnumake protobuf protobufc openssl zig];
    };
  };

  flake.nixosModules.build-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.build-tools
    ];
  };
}
