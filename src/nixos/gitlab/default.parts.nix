{ ... }: {
  perSystem =
    { mvs, ... }:
    {
      packages = {
        test-gitlab-runner-unstable = mvs.tip.testers.runNixOSTest (import ./runner.nix);

        test-gitlab-runner-2605 = (mvs.at "26.05").testers.runNixOSTest (import ./runner.nix);
      };
    };
}
