{...}: {
  flake.nixosModules.virtualization = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.features.virtualization.enable = lib.mkEnableOption "Virtualization (Podman, libvirt)";

    config = lib.mkIf config.features.virtualization.enable {
      virtualisation.podman = {
        enable = true;
        autoPrune.enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };
      virtualisation.oci-containers.backend = "podman";
      virtualisation.libvirtd.enable = true;
      virtualisation.spiceUSBRedirection.enable = true;
      programs.virt-manager.enable = true;

      environment.systemPackages = with pkgs; [
        podman-desktop
        dive
        podman-tui
        podman-compose
      ];
    };
  };
}
