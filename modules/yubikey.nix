{
  config,
  pkgs,
  self,
  inputs,
  lib,
  ...
}: {
  services.udev = {
    enable = true;
    extraRules = ''
      SUBSYSTEM="usb", ATTR{idVendor}=="1050", MODE="0660", GROUP="yubikey"
    '';
  };

  environment.systemPackages = with pkgs; [
    yubikey-manager
    yubikey-manager-qt
    yubikey-personalization
    yubikey-personalization-gui
  ];
}
