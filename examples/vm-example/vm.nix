# Everything which makes `./configuration.nix` runnable as a throw-away QEMU
# VM. Do **not** copy this into a production host configuration: it logs in as
# `root` with a well-known password and shares a host directory into the guest.
#
# The VM specific settings live under `virtualisation.vmVariant`, which is the
# configuration NixOS uses for `config.system.build.vm`.
{
  lib,
  pkgs,
  ...
}:
{
  networking.hostName = "vm-example";

  # Needed so the job containers can resolve the `nix-daemon-container` and the
  # `podman-daemon-container` by name.
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  environment.systemPackages = with pkgs; [
    git
    jq
  ];

  # Keeps the example quick to build.
  documentation.enable = lib.mkDefault false;
  services.speechd.enable = false;

  # This VM is thrown away together with its disk image, so tracking the
  # release is fine here. Pin this on a real host to the release you installed
  # with.
  system.stateVersion = lib.trivial.release;

  virtualisation.vmVariant =
    { config, ... }:
    let
      cfg = config.services.gitlab-runner-podman;
    in
    {
      virtualisation = {
        # Building a job and populating the Nix store volume needs some room.
        memorySize = 8192;
        cores = 4;
        diskSize = 32 * 1024;

        # No graphical window: the VM is driven over the serial console of the
        # terminal `nix run` was started in. Quit with `Ctrl-a x`.
        graphics = false;

        # `ssh -p 2222 root@localhost`
        forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
        ];

        # The host directory `$GITLAB_RUNNER_SECRETS_DIR` (set by the
        # `example-vm` wrapper, see `./run-vm.nix`) holds the runner
        # authentication token which `./configuration.nix` reads.
        #
        # `securityModel = "none"` keeps QEMU from touching extended
        # attributes on the host, which not every filesystem supports.
        sharedDirectories.gitlab-runner-secrets = {
          source = "$GITLAB_RUNNER_SECRETS_DIR";
          target = "/run/secrets/gitlab-runner";
          securityModel = "none";
        };
      };

      # Convenience for poking around in the VM.
      services.getty.autologinUser = "root";
      users.users.root.password = "root";

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PermitEmptyPasswords = false;
        };
      };

      users.motd = ''
        Gitlab runner example VM
        ========================

          Runner status:  systemctl status gitlab-runner.service
          Runner log:     journalctl -fu gitlab-runner.service
          Containers:     podman ps -a
          Images:         podman images

          Start a job container by hand:

            podman run --rm -it \
              --volumes-from '${cfg.nix-daemon.containerName}' \
              -v '${cfg.podman-daemon.volumes.socket.name}:/run/podman' \
              '${cfg.jobs.defaultImageName}' \
              bash -c 'export CI_PIPELINE_ID=123456 && \
                       gitlab-runner-pre-build-script && nix --version'

          Quit the VM with `Ctrl-a x`.
      '';
    };
}
