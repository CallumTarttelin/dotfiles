{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.misc-langs = pkgs.buildEnv {
      name = "misc-langs";
      paths = with pkgs; [ocaml zig];
    };
  };

  flake.nixosModules.misc-langs = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.misc-langs
    ];
  };
}
