{...}: {
  flake.nixosModules.greeter = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.greeter.enable = lib.mkEnableOption "TUI greeter with Hyprland/UWSM";

    config = lib.mkIf config.features.greeter.enable {
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
            user = "greeter";
          };
        };
      };
      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };
      programs.uwsm = {
        enable = true;
        waylandCompositors = {
          hyprland = {
            prettyName = "Hyprland";
            comment = "Hyprland compositor managed by UWSM";
            binPath = "/run/current-system/sw/bin/start-hyprland";
          };
        };
      };
      security.pam.services.greetd.enableGnomeKeyring = true;
    };
  };
}
