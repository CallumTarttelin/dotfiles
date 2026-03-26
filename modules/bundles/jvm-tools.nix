{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.jvm-tools = pkgs.buildEnv {
      name = "jvm-tools";
      # jdk21 and gradle installed via HM programs.java/programs.gradle
      paths = with pkgs; [maven];
    };
  };

  flake.nixosModules.jvm-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.jvm-tools
    ];
  };
}
