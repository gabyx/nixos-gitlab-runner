{ inputs, ... }: {
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs-gitlab { inherit system; };
    in
    {
      packages = {
        test-gitlab-runner = pkgs.testers.runNixOSTest (import ./runner.nix);
      };
    };
}
