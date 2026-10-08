# Exposes the example NixOS VM.
{
  inputs,
  lib,
  self,
  withSystem,
  ...
}:
let
  vmSystem = "x86_64-linux";
in
{
  # The NixOS configuration.
  flake.nixosConfigurations = {
    vm-example = withSystem vmSystem (
      { pkgs, ... }:
      inputs.nixpkgs.lib.nixosSystem {
        modules = [
          # Use the same `nixpkgs` the rest of this flake uses.
          { nixpkgs.pkgs = pkgs; }

          self.nixosModules.gitlab-runner-podman

          ./vm-example/dummy-stuff.nix

          ./vm-example/vm.nix
          ./vm-example/virtualization.nix
          ./vm-example/runner.nix
        ];
      }
    );
  };

  # The run script.
  perSystem =
    { pkgs, system, ... }:
    {
      packages = lib.optionalAttrs (system == vmSystem) {
        vm-example = pkgs.callPackage ./vm-example/run-vm.nix {
          inherit (self.nixosConfigurations.vm-example.config.system.build) vm;
        };
      };
    };
}
