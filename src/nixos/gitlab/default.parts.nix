_:
{
  perSystem = { pkgs, ... }: {
    packages = {
      test-gitlab-runner = pkgs.testers.runNixOSTest (import ./runner.nix);
    };
  };
}
