{ lib, ... }: {
  # Placeholder hardware settings. They only exist such that the plain
  # (non-VM) configuration passes its assertions, i.e. that
  # `nixosConfigurations.vm-example.config.system.build.toplevel` builds.
  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/nixos";
    fsType = lib.mkDefault "ext4";
  };
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
}
