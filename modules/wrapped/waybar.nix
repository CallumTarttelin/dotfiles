# TODO: Bake waybar config + CSS into this wrapper.
# For now just wraps the bare waybar package so it's available as packages.myWaybar.
{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.myWaybar = pkgs.waybar;
  };

  flake.nixosModules.waybar = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myWaybar
    ];
  };
}
