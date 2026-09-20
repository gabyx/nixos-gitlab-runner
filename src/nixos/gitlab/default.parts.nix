{ ... }: {
  perSystem =
    { mvs, ... }:
    let
      testModule = import ./runner-test.nix;
    in
    {
      packages = {
        test-gitlab-runner-unstable = mvs.tip.testers.runNixOSTest testModule;
        test-gitlab-runner-2605 = (mvs.at "26.05").testers.runNixOSTest testModule;
      };
    };
}
