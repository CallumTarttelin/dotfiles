_: {
  flake.nixosModules.network = _: {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };

    services.resolved.enable = true;

    networking = {
      networkmanager = {
        enable = true;
        wifi.backend = "iwd";
        wifi.powersave = false;
        dns = "systemd-resolved";
        unmanaged = [
          "interface-name:tailscale*"
          "interface-name:veth-*"
          "interface-name:virbr*"
          "interface-name:vnet*"
          "interface-name:docker*"
          "interface-name:br-*"
          "interface-name:wpan*"
        ];
        settings.device."wifi.iwd.autoconnect" = false;
      };
      nftables.enable = true;

      firewall = {
        enable = true;
        checkReversePath = "loose";
        trustedInterfaces = ["tailscale0" "wpan0"];
      };

      nameservers = [
        "1.1.1.1"
        "1.0.0.1"
      ];
      search = [
        "oryx-harmonic.ts.net"
      ];
    };
  };
}
