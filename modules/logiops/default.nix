{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    logiops
  ];

  environment.etc = {
    "logid.cfg" = {
      source = ./logid.cfg;
      mode = "0644";
    };
  };

  systemd.services.logiops = {
    enable = true;
    description = "Logitech Configuration Daemon";

    unitConfig = {
      Type = "simple";
    };

    serviceConfig = {
      ExecStart = "${pkgs.logiops}/bin/logid";
    };

    wantedBy = ["multi-user.target"];
  };
}
