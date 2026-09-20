{ pkgs, ... }:
let

  # We need proper derivations to add it to the nixImageBase.
  mkDrv =
    name: src:
    pkgs.stdenv.mkDerivation {
      inherit name src;
      installPhase = ''
        mkdir -p $out
        cp -r $src/* $out/
      '';
    };

  commonRoot = mkDrv "common-root-files" ./common-root;
  containers = mkDrv "containers-files" ./containers;
  nixImage = mkDrv "nix-image-files" ./nix-image;
  alpineImage = mkDrv "alpine-image-files" ./alpine-image;
  ubuntuImage = mkDrv "ubuntu-image-files" ./ubuntu-image;
  fakeNixpkgs = mkDrv "fake-nixpkgs-files" ./fake-nixpkgs;

  all = [
    commonRoot
    containers
    nixImage
    alpineImage
    ubuntuImage
    fakeNixpkgs
  ];
in
{
  inherit
    commonRoot
    containers
    nixImage
    alpineImage
    ubuntuImage
    fakeNixpkgs
    all
    ;

}
