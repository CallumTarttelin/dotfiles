{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.web-tools = pkgs.buildEnv {
      name = "web-tools";
      paths = with pkgs; [nodejs_24 pnpm deno bun];
    };
  };

  flake.nixosModules.web-tools = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.web-tools
    ];
  };
}
