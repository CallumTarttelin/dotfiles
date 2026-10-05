{
  pkgs,
  inputs,
  lib,
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

  # Linux 7.2 provides the Steam Frame adapter's rtw89_8852cu driver.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=GB
  '';

  networking.hostName = "nixshark";

  # Let Steam configure its adapter through NetworkManager while iwd and
  # networkd continue managing the existing LAN connection.
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
    dns = "systemd-resolved";
    unmanaged = ["*" "except:interface-name:steamframe0"];
    settings."device-steam-frame" = {
      match-device = "interface-name:steamframe0";
      "wifi.iwd.autoconnect" = false;
    };
  };
  # NetworkManager otherwise disables the existing networkd DHCP defaults.
  networking.useDHCP = lib.mkForce true;
  networking.wireless.iwd.settings.General.Country = "GB";
  systemd.network.networks."10-steam-frame" = {
    matchConfig.Name = "steamframe0";
    linkConfig.Unmanaged = true;
  };

  programs.steam.remotePlay.openFirewall = true;

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
    ACTION=="add", SUBSYSTEM=="net", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2432", NAME="steamframe0", ENV{ID_NET_MANAGED_BY}="org.freedesktop.NetworkManager"
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
