{...}: {
  flake.nixosModules.logiops = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.logiops.enable = lib.mkEnableOption "Logitech mouse daemon (logiops)";

    config = lib.mkIf config.features.logiops.enable {
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
        serviceConfig = {
          ExecStart = "${pkgs.logiops}/bin/logid";
        };
        wantedBy = ["multi-user.target"];
      };
    };
  };
}
