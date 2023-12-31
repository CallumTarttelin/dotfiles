# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = ["amdgpu"];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/bbb8b5da-f7c4-459e-a834-75cfbdefcf1b";
    fsType = "btrfs";
    options = ["subvol=@"];
  };

  boot.initrd.luks.devices."luks-ee6977f5-36b5-41c8-a06c-b519c7f99b43".device = "/dev/disk/by-uuid/ee6977f5-36b5-41c8-a06c-b519c7f99b43";
  boot.initrd.luks.devices."luks-0294d4cc-4513-46ea-b430-167f12fc13e3".device = "/dev/disk/by-uuid/0294d4cc-4513-46ea-b430-167f12fc13e3";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8A22-6544";
    fsType = "vfat";
  };

  swapDevices = [
    {device = "/dev/disk/by-uuid/670529fa-962b-426c-b436-961a40c99f1e";}
  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp1s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
