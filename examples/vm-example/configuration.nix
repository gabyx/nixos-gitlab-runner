# Example configuration for a NixOS host which runs a Gitlab runner with the
# `podman` executor (see the repository `README.md`).
#
# This is the part you want to copy into your own NixOS host configuration.
# Everything which only exists to make this runnable as a throw-away QEMU VM
# lives in `./vm.nix`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gitlab-runner-podman;

  # The runner authentication token is read from this file. In this example the
  # host directory `$GITLAB_RUNNER_SECRETS_DIR` is shared into the VM at
  # `/run/secrets/gitlab-runner` (see `./vm.nix`). On a real host use
  # `sops-nix`, `agenix` or a `systemd` credential instead.
  #
  # The file is an environment file of the form:
  #
  # ```
  # CI_SERVER_URL=https://gitlab.com
  # CI_SERVER_TOKEN=glrt-xxxxxxxxxxxxxxxxxxxx
  # ```
  tokenFile = "/run/secrets/gitlab-runner/token.env";
in
{
  # Enable the job images, the Nix daemon container and the podman daemon
  # container. The runner below is configured against them.
  services.gitlab-runner-podman = {
    enable = true;

    # Prune containers, images and volumes which are not labeled `no-prune`
    # once a day. All images built by this module carry that label.
    autoPrune.enable = true;

    # Job images for the runner.
    jobs = {
      # Additional packages in the `local/alpine` job image. They are registered
      # as garbage collector roots in the Nix daemon container, such that they
      # survive a garbage collection.
      alpine.content = [
        pkgs.jq
        pkgs.rsync
      ];
    };
  };

  services.gitlab-runner = {
    enable = true;

    settings = {
      log_level = "debug";
    };

    gracefulTermination = false;

    # See: https://search.nixos.org/options?query=services.gitlab-runner.services
    services.nix-runner = {
      description = "Nix runner (podman executor, shared containerized Nix store)";

      # `cfg.registrationFlags` wires the job container to the scratch volume,
      # to the podman daemon socket and to the read-only Nix store of the Nix
      # daemon container. Append your own flags here.
      registrationFlags = cfg.registrationFlags;

      authenticationTokenConfigFile = tokenFile;

      executor = "docker";
      dockerImage = cfg.jobs.defaultImageName;
      dockerAllowedImages = [ ];
      dockerPrivileged = false;
      requestConcurrency = 4;
      preBuildScript = "${lib.getExe cfg.preBuildScript}";
    };
  };
}
