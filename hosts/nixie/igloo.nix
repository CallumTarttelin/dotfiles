{config, ...}: {
  services.igloo = {
    enable = true;
    # The local CLI can read its runner token without sudo.
    user = "tarttelin";
    cpus = 8;
    # Aggregate guest RAM budget; host and VM-helper overhead is additional.
    memoryMiB = 16 * 1024;
    listen = "127.0.0.1:7890";
    environmentFile = config.age.secrets.igloo-api.path;
    # Checkpoints work immediately with a local object directory. The runner
    # also supports Garage/S3 via environmentFile and localObjectDirectory=null.
  };

  # Guest SSH and forwards use nixie as a jump host over the tailnet.
  services.tailscale.extraSetFlags = ["--ssh"];

  services.caddy.virtualHosts."igloo.callumtarttelin.com".extraConfig = ''
    tls /var/lib/acme/callumtarttelin.com/fullchain.pem /var/lib/acme/callumtarttelin.com/key.pem {
      protocols tls1.3
    }
    reverse_proxy http://127.0.0.1:7890
  '';
}
