{
  inputs,
  lib,
  self,
  ...
}:
{
  perSystem =
    {
      system,
      ...
    }:
    let
      p = self.lib.nixpkgs.importPkgs { inherit system; };

      pkgs =
        assert lib.assertMsg (
          p.multiverse.rev == inputs.nixpkgs.rev
        ) "Input 'nixpkgs' (unstable) must be aligned with `importPkgs` '${p.multiverse.rev}'.";
        p;

      pkgsStable = self.lib.nixpkgs.importPkgsStable { inherit system; };

      mvs = self.lib.nixpkgs.mkMultiverse { inherit system; };
    in
    {
      # Define two arguments `pkgs` and `pkgsStable` available on all flake-parts modules.
      _module.args.pkgs = pkgs;
      _module.args.pkgsStable = pkgsStable;
      _module.args.mvs = mvs;

      legacyPackages.unstable = pkgs;
      legacyPackages.stable = pkgsStable;
    };
}
