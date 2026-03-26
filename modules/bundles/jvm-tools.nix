{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.jvm-tools = pkgs.buildEnv {
      name = "jvm-tools";
      paths = with pkgs; [jdk21 gradle maven];
    };
  };

  flake.nixosModules.jvm-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.jvm-tools
    ];
  };
}
