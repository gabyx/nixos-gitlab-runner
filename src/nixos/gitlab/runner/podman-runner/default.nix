# Gitlab Podman Runner NixOS Module
#
# This module will add a Gitlab-Runner
# with a nix-daemon running in a podman container `nix-daemon-container`.
# Check the documentation in the NixOS Manual.
#
# Debugging on the VM:
#
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

  # Some scripts we use.
  updateNixStoreVolume = pkgs.callPackage ./scripts/copy-to-nix-store.nix {
    image = nixDaemonImage.imageName + ":" + nixDaemonImage.imageTag;
    imageDrv = nixDaemonImage;
  };

  # These derivations are symlinked into the job images root dir.
  jobImgs = import ./job-images.nix {
    inherit lib pkgs cfg;
  };

  # This is the Nix base image used for the Nix Daemon.
  # The build script for the nixos/nix image is vendored due to Hydra limitations.
  # cause it is IFD (Import from Derivation) which is not allowed.
  # You can set `cfg.images.nix-daemon.`
  nixImageBaseFn =
    if cfg.nix-daemon.builder.enable != null then
      cfg.nix-daemon.builder.func
    else
      import (
        (pkgs.fetchFromGitHub {
          owner = "NixOS";
          repo = "nix";
          rev = cfg.nix-daemon.version;
          hash = cfg.nix-daemon.hash;
        })
        + "/docker.nix"
      );

  nixDaemonImageBase = pkgs.callPackage nixImageBaseFn {
    inherit (cfg.nix-daemon) nixConf;
    name = "local/nix-base";
    tag = "latest";
    bundleNixpkgs = false;
    maxLayers = 2;
  };

  # This is the daemon image which provides the store
  # as volumes.
  nixDaemonImage = pkgs.dockerTools.buildLayeredImage {
    fromImage = nixDaemonImageBase;
    inherit (cfg.nix-daemon) name tag;

    inherit (cfg.nix-daemon) extraCommands;

    # Add all store paths and make them GC roots, so we dont loose them.
    # NOTE: Cannot add it to `extraPkgs` cause of the profile
    #       which uses `buildEnv` which collides.
    fakeRootCommands =
      let
        allPkgs = jobImgs.allStoreDrv ++ cfg.nix-daemon.content;
      in
      # bash
      ''
        mkdir -p nix/var/nix/gcroots/additional-pkgs
        ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "Adding package '${pkg}'"
          ln -fs "${pkg}" "nix/var/nix/gcroots/additional-pkgs/"
        '') allPkgs}
      ''
      + cfg.nix-daemon.fakeRootCommands;

    config = {
      Volumes = {
        "/nix/store" = { };
        "/nix/var/nix/db" = { };
        "/nix/var/nix/daemon-socket" = { };
      };
      Labels = cfg.images.noPruneLabels;
    };

    maxLayers = cfg.nix-daemon.maxLayers;
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

  nixDaemonContainer = {
    imageFile = nixDaemonImage;
    image = "${cfg.nix-daemon.name}:${cfg.nix-daemon.tag}";

    volumes = [
      "${cfg.nix-daemon.volumes.store.name}:/nix/store"
      "${cfg.nix-daemon.volumes.db.name}:/nix/var/nix/db"
      "${cfg.nix-daemon.volumes.socket.name}:/nix/var/nix/daemon-socket"
      # TODO: Add signing key.
      # "${config.sops.secrets.nix-store-signing-key.path}:${config.sops.secrets.nix-store-signing-key.path}:ro"
    ];
    cmd = [
      "nix"
      "daemon"
    ];
  };

  podmanDaemonContainer = {
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

    "--docker-host"
    "unix:///var/run/podman/podman.sock"

    "--docker-network-mode"
    "bridge"
  ];

  # Define the containers for the jobs.
  # This is a trick to add the job images to the registry.
  # TODO: Can this be done better?
  # On `nix` also make the scratch directory world readable.
  jobContainers = (
    lib.concatMapAttrs (
      name: image:
      let
        imgCfg = cfg.jobs.${name};
      in
      {
        "${imgCfg.containerName}" = {
          imageFile = image;
          image = "${imgCfg.name}:${imgCfg.tag}";

          extraOptions = [
            "--volumes-from"
            "${cfg.nix-daemon.containerName}:ro"
          ];

          dependsOn = [ cfg.nix-daemon.containerName ];
          cmd = [ "true" ];
        }
        // (lib.optionalAttrs (name == "nix") {
          volumes = [ "${cfg.volumes.scratch.name}:/scratch" ];
          cmd = [
            "chmod"
            "777"
            "/scratch"
          ];
        });
      }
    ) jobImgs.images
  );

  # Do not restart systemd service for the job images.
  # Otherwise they get readded always.
  modifiedJobServices = lib.concatMapAttrs (
    name: image:
    let
      imgCfg = cfg.jobs.${name};
      containers = config.virtualisation.oci-containers.containers;
      serviceName = containers."${imgCfg.containerName}".serviceName;
    in
    {
      "${serviceName}".serviceConfig = {
        Restart = lib.mkForce "no";
      };
    }
  ) jobImgs.images;
in
{
  imports = [ ./options.nix ];

  # Enable Podman.
  virtualisation.podman = {
    enable = true;
    autoPrune = lib.mkIf cfg.autoPrune.enable {
      dates = "daily";
      flags = [
        "--filter"
        "label!=no-prune"
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
    containers = jobContainers // {
      "${cfg.nix-daemon.containerName}" = nixDaemonContainer;
      "${cfg.podman-daemon.containerName}" = podmanDaemonContainer;
    };
  };

  # Define some systemd modifications.
  systemd.services =
    let
      containers = config.virtualisation.oci-containers.containers;
      nixDaemonSrv = containers."${cfg.nix-daemon.containerName}".serviceName;
    in
    modifiedJobServices
    // {
      # Update Nix store in the daemon service.
      # The job images do not contain any actual store paths and are very small.
      # We add `allStoreDrvs` to the nix store volume `nix-daemon-store` of the
      # `nixDaemonImageBase` to make everything available on the job images
      # (they mount `nix-daemon-store`).
      # But when you delete the volume for cleanup or space reasons, this
      # service initializes the store correctly again.
      # Note: Podman, when starting the `nix-daemon-container`, copies all `/nix/store` paths
      # from the image to the `nix-daemon-store` volume before running it.
      update-nix-daemon-store = {
        description = "update-nix-daemon-store";
        restartIfChanged = true;
        wantedBy = [ "multi-user.target" ];

        # Ensure that the bootstrap is restarted when `nix-daemon-container` is.
        partOf = [ "${nixDaemonSrv}.service" ];

        script = ''
          ${lib.getExe updateNixStoreVolume}
        '';

        serviceConfig = {
          Type = "oneshot";
          SupplementaryGroups = "podman";
          User = "root";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };

      # Start 'nix-daemon-container' after the update of the volume.
      "${nixDaemonSrv}".after = [ "update-nix-daemon-store.service" ];

      # Start Runner after nix-daemon-container.
      gitlab-runner.after = [ "${nixDaemonSrv}.service" ];
    };
}
