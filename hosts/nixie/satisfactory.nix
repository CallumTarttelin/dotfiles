# Satisfactory Archipelago dedicated server; see satisfactory.md for setup.
# Custom LinuxServer mod is staged separately in the persistent data directory.
{lib, ...}: {
  virtualisation.podman.enable = true;
  virtualisation.oci-containers = {
    backend = "podman";
    containers.satisfactory = {
      # After validation, replace latest with the tested image's @sha256 digest.
      image = "docker.io/wolveix/satisfactory-server:latest";
      autoStart = true;
      volumes = ["/home/tarttelin/.local/share/satisfactory:/config"];
      environment = {
        PUID = "1000"; # tarttelin on nixie
        PGID = "100"; # users on nixie
        MAXPLAYERS = "4";
        SERVERGAMEPORT = "7777";
        SERVERMESSAGINGPORT = "8889"; # 8888 is already occupied on nixie
        STEAMBETA = "false";
        # The image downloads on the first start even with this set to true.
        # Subsequent starts preserve the installed game version for mod testing.
        SKIPUPDATE = "true";
        LOG = "true";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };
      extraOptions = [
        "--network=host"
        "--memory=32g"
        "--stop-timeout=120"
      ];
    };
  };

  # Host networking uses the host firewall, with no container port translation.
  networking.firewall.allowedTCPPorts = [7777 8889];
  networking.firewall.allowedUDPPorts = [7777];

  systemd.tmpfiles.rules = [
    "d /home/tarttelin/.local/share/satisfactory 0750 tarttelin users -"
  ];
  systemd.services.podman-satisfactory = {
    after = ["systemd-tmpfiles-setup.service"];
    serviceConfig = {
      # The OCI module already sets TimeoutStartSec = 0 (unlimited).
      TimeoutStopSec = lib.mkForce 150;
    };
  };
}
