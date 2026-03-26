{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.jvm-tools = pkgs.buildEnv {
      name = "jvm-tools";
      paths = with pkgs; [jdk21 gradle maven];
    };

    # For per-project devShells: inputsFrom = [ dotfiles.devShells.x86_64-linux.jvm ];
    # jdk's setup-hook automatically sets JAVA_HOME in mkShell context
    devShells.jvm = pkgs.mkShell {
      packages = with pkgs; [jdk21 gradle maven];
    };
  };

  flake.nixosModules.jvm-tools = {pkgs, ...}: {
    home-manager.users.tarttelin = {
      home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.jvm-tools
      ];
      programs.java = {
        enable = true;
        package = pkgs.jdk21;
      };
      programs.gradle.enable = true;
    };
  };
}
