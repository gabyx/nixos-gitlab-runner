{ ... }: {
  flake.nixosModules = {
    gitlab-runner-podman = import ./runner/podman-runner;
  };
}
