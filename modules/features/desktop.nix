_: {
  flake.nixosModules.desktop = {
    config,
    lib,
    ...
  }: {
    options.features.desktop.enable = lib.mkEnableOption "desktop environment defaults";

    config = lib.mkIf config.features.desktop.enable {
      # Wrapped desktop packages
      wrapped.ghostty.enable = lib.mkDefault true;
      wrapped.foot.enable = lib.mkDefault true;
      wrapped.starship.enable = lib.mkDefault true;
      wrapped.mako.enable = lib.mkDefault true;
      wrapped.wofi.enable = lib.mkDefault true;
      wrapped.waybar.enable = lib.mkDefault true;

      # Desktop app bundles
      bundles.social.enable = lib.mkDefault true;
      bundles.editors.enable = lib.mkDefault true;
      bundles.office.enable = lib.mkDefault true;
      bundles.llms.enable = lib.mkDefault true;
      bundles.media.enable = lib.mkDefault true;
      bundles.drawing.enable = lib.mkDefault true;
      bundles.electronics.enable = lib.mkDefault true;
      bundles.work.enable = lib.mkDefault true;
    };
  };
}
