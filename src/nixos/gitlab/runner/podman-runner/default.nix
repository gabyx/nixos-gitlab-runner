# Gitlab Podman Runner NixOS Module
#
# This module will add a Gitlab-Runner
# with a nix-daemon running in a podman container `nix-daemon-container`.
# Check the documentation in the NixOS Manual.
#
# Debugging on the VM:
# - You can use `journalctl -u gitlab-runner.service`.
#
# - To run a job container inside the VM use:
#   ```bash
#      podman run --rm -it
#      --volumes-from 'nix-daemon-container'
#      -v "podman-daemon-socket:/run/podman"
#      "local/alpine" \
#      bash -c "export CI_PIPELINE_ID=123456 && gitlab-runner-pre-build-script; echo hello"
#   ```
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gitlab-runner-podman;

  jobImagePkgs = if cfg.jobs.pkgs != null then cfg.jobs.pkgs else pkgs;

  # These derivations are symlinked into the job images root dir.
  jobImgs = import ./job-images.nix {
    inherit lib cfg;
    pkgs = jobImagePkgs;
  };

  # The Nix daemon image, container and store update script.
  nixDaemon = import ./nix-daemon.nix {
    inherit lib pkgs cfg;
    # These are paths which are only symlinked in the job images.
    storePaths = cfg.nix-daemon.content ++ jobImgs.allStoreDrv;
  };

  loadJobImages = pkgs.callPackage ./scripts/load-job-images.nix { inherit (jobImgs) images; };

  ciUid = toString cfg.ciUser.uid;
  podmanSocket =
    if cfg.ciUser.name == "root" then
      "/var/run/podman/podman.sock"
    else
      "/run/user/${toString config.users.users.${cfg.ciUser.name}.uid}/podman/podman.sock";

  remotePodman = {
    environment.CONTAINER_HOST = "unix://${podmanSocket}"; # podman acts as a remote client
    after = [ "user@${ciUid}.service" ];
    wants = [ "user@${ciUid}.service" ];
  };

  # This is the podman daemon image which enables
  # a job image to use `podman` internally.
  podmanDaemonImage =
    let
      # Update with:
      # ```shell
      # nix run "github:nixos/nixpkgs/nixos-unstable#nix-prefetch-docker" -- \
      #    --image-name quay.io/podman/stable --image-tag v5.6.0
      # ```
      base = pkgs.dockerTools.pullImage {
        inherit (cfg.podman-daemon) imageName imageDigest hash;
        finalImageName = cfg.podman-daemon.imageName;
        finalImageTag = "latest";
      };
    in
    pkgs.dockerTools.buildLayeredImage {
      fromImage = base;
      inherit (cfg.podman-daemon) name tag;

      config = {
        Labels = cfg.images.noPruneLabels;
      };
    };

  podmanDaemonContainer = {
    podman.user = cfg.ciUser.name;

    imageFile = podmanDaemonImage;
    image = "${cfg.podman-daemon.name}:${cfg.podman-daemon.tag}";

    volumes = [
      "${cfg.podman-daemon.volumes.socket.name}:/run/podman"
      "${cfg.podman-daemon.volumes.cache.name}:/var/lib/container"

      # Shared images, currently not needed.
      "${cfg.podman-daemon.volumes.shared.name}:/var/lib/shared:ro"
    ];

    privileged = true;

    cmd = [
      "podman"
      "system"
      "service"
      "--time=0"
      "unix:///run/podman/podman.sock"
      "--log-level"
      "info"
    ];
  };

  registrationFlags = [
    "--docker-volumes"
    "${cfg.volumes.scratch.name}:/scratch"

    "--docker-volumes"
    "${cfg.podman-daemon.volumes.socket.name}:/run/podman"

    "--docker-volumes-from"
    "${cfg.nix-daemon.containerName}:ro"

    "--docker-network-mode"
    "podman"

    "--docker-host"
    "unix://${podmanSocket}"
  ]
  ++ (lib.optionals (cfg.jobs.enable) [
    # Only use images from the local store: the job images are built by Nix
    # and exist in the store, so dont pull them.
    "--docker-pull-policy"
    "if-not-present"

    "--docker-allowed-pull-policies"
    "if-not-present"
  ]);

  # Init container to setup stuff.
  # If you add stuff here also add the systemd stuff below.
  setupContainers =
    let
      imgCfg = cfg.jobs.nix;
      image = jobImgs.images.nix;
    in
    {
      setup-scratch = {
        podman.user = cfg.ciUser.name;

        imageFile = image;
        image = "${imgCfg.name}:${imgCfg.tag}";

        extraOptions = [
          "--volumes-from"
          "${cfg.nix-daemon.containerName}:ro"
        ];

        dependsOn = [ cfg.nix-daemon.containerName ];

        volumes = [ "${cfg.volumes.scratch.name}:/scratch" ];
        cmd = [
          "chmod"
          "777"
          "/scratch"
        ];
      };
    };
in
{
  imports = [
    ./options.nix
    ./user.nix
  ];

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = false;

    # Enable Podman.
    virtualisation.podman = {
      enable = true;

      dockerSocket = {
        # Needed for gitlab-runner to set the correct permissions.
        # on the gitlab-runner systemd service.
        enable = true;
      };

      autoPrune = lib.mkIf cfg.autoPrune.enable {
        enable = true;
        dates = "daily";

        # Never prune the images built by this module, they would need to be
        # rebuilt on the next job.
        flags =
          (lib.concatMap (label: [
            "--filter"
            "label!=${label}"
          ]) (lib.attrNames cfg.images.noPruneLabels))
          ++ [
            "--volumes"
            "--log-level"
            "debug"
          ];
      };
    };

    # Set computed stuff on config.
    services.gitlab-runner-podman = {
      inherit registrationFlags;
      inherit (jobImgs) preBuildScript;
    };

    # Register all containers.
    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        "${cfg.nix-daemon.containerName}" = nixDaemon.container;
        "${cfg.podman-daemon.containerName}" = podmanDaemonContainer;
      }
      // setupContainers;
    };

    # Define some systemd modifications.
    systemd.services =
      let
        containers = config.virtualisation.oci-containers.containers;
        nixDaemonSrv = containers.${cfg.nix-daemon.containerName}.serviceName;
      in
      {
        # Start Gitlab runner after nix daemon.
        gitlab-runner = {
          after = [
            "${nixDaemonSrv}.service"
            "linger-users.service"
          ];
        }
        // lib.optionalAttrs (cfg.ciUser != "root") {
          serviceConfig = {
            SupplementaryGroup = [ ];
            User = cfg.ciUser.name;
          };
        };

        # Start nix-daemon-container before gitlab-runner.
        "${nixDaemonSrv}.service" = {
          before = [ "gitlab-runner.service" ];
          wantedBy = [ "gitlab-runner.service" ];
        };

        # Setup containers.
        # "podman-setup-scratch" = remotePodman;
      }
      // (lib.optionalAttrs (cfg.jobs.enable) {
        # Load all job images.
        podman-load-job-images = lib.mkMerge [
          remotePodman
          {
            description = "Load all job images into podman.";
            wantedBy = [ "multi-user.target" ];
            after = [
              "${nixDaemonSrv}.service"
              "podman.service"
            ];
            before = [ "gitlab-runner.service" ];
            requires = [ "${nixDaemonSrv}.service" ];
            path = [ config.virtualisation.podman.package ];

            serviceConfig = {
              User = cfg.ciUser.name;
              Type = "oneshot";
              StandardOutput = "journal";
              StandardError = "journal";
            };

            script = "${lib.getExe loadJobImages}";
          }
        ];

        # Update Nix store in the daemon service.
        # The job images do not contain any actual store paths and are very small.
        # We add `allStoreDrvs` to the nix store volume `nix-daemon-store` of the
        # Nix daemon image to make everything available on the job images
        # (they mount `nix-daemon-store`).
        # But when you delete the volume for cleanup or space reasons, this
        # service initializes the store correctly again.
        # Note: Podman, when starting the `nix-daemon-container`, copies all `/nix/store` paths
        # from the image to the `nix-daemon-store` volume before running it.
        update-nix-daemon-store = lib.mkMerge [
          remotePodman
          {
            description = "update-nix-daemon-store";
            restartIfChanged = true;

            before = [ "${nixDaemonSrv}.service" ];

            wantedBy = [
              "multi-user.target"
              "${nixDaemonSrv}.service"
            ];

            script = ''
              ${lib.getExe nixDaemon.updateStoreVolume}
            '';

            serviceConfig = {
              Type = "oneshot";
              User = cfg.ciUser.name;
              StandardOutput = "journal";
              StandardError = "journal";
            };
          }
        ];
      });
  };
}
