{lib, ...}:
# networking configuration
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  networking = {
    firewall.enable = true;
    firewall.checkReversePath = "loose";

    networkmanager = {
      enable = true;
      wifi.powersave = true;
    };

    nameservers = [
      "100.100.100.100"
      "1.1.1.1"
      "1.0.0.1"
    ];
    search = [
      "tail86813.ts.net"
    ];
  };

  # Don't wait for network startup
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
}
