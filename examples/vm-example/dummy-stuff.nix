{ lib, ... }: {
  # Placeholder hardware settings. They only exist such that the plain
  # (non-VM) configuration passes its assertions, i.e. that
  # `nixosConfigurations.vm-example.config.system.build.toplevel` builds.
  # On a real host these come from the generated `hardware-configuration.nix`.
  #
  # The VM variant below does not use them: `qemu-vm.nix` defines
  # `fileSystems."/"` from `virtualisation.rootDevice` (normal priority, which
  # beats `mkDefault`) and `boot.loader.grub.device` with `mkVMOverride`.
  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/nixos";
    fsType = lib.mkDefault "ext4";
  };
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
}
