_: {
  flake.nixosModules.network = {lib, ...}: {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };

    services.resolved.enable = true;
    systemd.network.enable = true;

    networking = {
      wireless.iwd.enable = true;
      useNetworkd = true;
      nftables.enable = true;

      firewall = {
        enable = true;
        checkReversePath = "loose";
        trustedInterfaces = ["tailscale0" "wpan0"];
      };

      nameservers = [
        "100.100.100.100"
        "1.1.1.1"
        "1.0.0.1"
      ];
      search = [
        "oryx-harmonic.ts.net"
      ];
    };

    systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
  };
}
