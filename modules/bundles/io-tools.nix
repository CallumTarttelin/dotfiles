{self, ...}: {
  perSystem = {pkgs, ...}: {
    packages.io-tools = pkgs.buildEnv {
      name = "io-tools";
      paths = with pkgs; [
        # network
        dig
        (pkgs.symlinkJoin {
          name = "inetutils-no-collisions";
          paths = [inetutils];
          postBuild = ''
            rm -f $out/bin/{ping,ping6,traceroute,whois}
          '';
        })
        tcpdump
        iptables
        nmap
        traceroute
        whois
        mtr
        socat
        iperf3
        ethtool
        # usb / hardware
        usbutils
        pciutils
        smartmontools
        dmidecode
        # general io debug
        lsof
        strace
      ];
    };
  };

  flake.nixosModules.io-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.io-tools.enable = lib.mkEnableOption "io tools (network, usb, hardware debugging)";
    config = lib.mkIf config.bundles.io-tools.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.io-tools
      ];
    };
  };
}
