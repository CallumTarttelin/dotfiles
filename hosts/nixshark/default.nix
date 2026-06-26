{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./backup.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking.hostName = "nixshark";

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.x86_64-linux.default
    xdg-utils
    aoc-cli
    via
    vial
    socat
    bubblewrap
  ];

  services.xserver.videoDrivers = ["amdgpu"];

  services.flatpak.enable = true;

  powerManagement = {
    enable = true;
    powertop.enable = false;
  };

  services.syncthing = {
    enable = true;
    user = "tarttelin";
    dataDir = "/home/tarttelin/sync";
    configDir = "/home/tarttelin/.config/syncthing";
  };

  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0660", GROUP="100", TAG+="uaccess", TAG+="udev-acl"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="100", TAG+="uaccess", TAG+="udev-acl"
  '';

  systemd.services.disable-wakeups = {
    description = "Disable GPP0 wakeup trigger";
    wantedBy = ["multi-user.target"];
    after = ["systemd-udev-settle.service"];
    script = ''
      if grep -q "GPP0.*enabled" /proc/acpi/wakeup; then
        echo GPP0 > /proc/acpi/wakeup
        echo "GPP0 wakeup trigger disabled"
      else
        echo "GPP0 wakeup trigger is already disabled"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  system.stateVersion = "22.11";
}
