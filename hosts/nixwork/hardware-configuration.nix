{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "sd_mod"];
    initrd.kernelModules = ["amdgpu"];
    # https://github.com/NixOS/nixos-hardware/blob/master/common/cpu/amd/pstate.nix
    # https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html
    kernelParams = ["initcall_blacklist=acpi_cpufreq_init"];
    kernelModules = ["kvm-amd" "amd-pstate"];
    extraModulePackages = [];
  };

  # Filesystems

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/home";
    fsType = "btrfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  swapDevices = [
    {device = "/dev/disk/by-label/SWAP";}
  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.docker0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp5s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.virbr0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlan0.useDHCP = lib.mkDefault true;

  services.fstrim.enable = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
