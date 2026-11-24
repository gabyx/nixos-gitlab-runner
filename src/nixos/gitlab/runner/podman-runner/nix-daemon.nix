# The Nix daemon image and container which provides the
# Nix store over volumes to all job containers.
{
  lib,
  pkgs,
  cfg,
  # All store paths which must stay alive in the Nix daemon store.
  storePaths,
}:
let
  # The registration (validity info) of the closure of `storePaths`.
  # `buildLayeredImage` copies these paths into the image but does not
  # register them in the Nix database of the image. Nix ignores GC roots to
  # unregistered paths and the garbage collector deletes unregistered paths,
  # so they get registered with `nix-store --load-db` at runtime.
  storeRegistration = pkgs.closureInfo { rootPaths = storePaths; };

  # The directory in the Nix daemon image where the files `registration` and
  # `store-paths` of `storeRegistration` are copied to.
  # It must not be in `/nix/store` (it would be unregistered itself) and
  # not in a volume (it would not be updated with the image).
  storeRegistrationDir = "/nix/var/nix/registration";

  # Register all paths in `storeRegistrationDir` and start the daemon.
  startScript =
    # bash
    ''
      set -eu

      missing=0
      while read -r path; do
        if [ ! -e "$path" ]; then
          echo "Store path '$path' is missing." >&2
          missing=1
        fi
      done <"${storeRegistrationDir}/store-paths"

      if [ "$missing" = "0" ]; then
        echo "Register store paths from '${storeRegistrationDir}/registration'." >&2
        nix-store --load-db <"${storeRegistrationDir}/registration"
      else
        echo "WARNING: Not registering store paths, some are missing." >&2
        echo "         Restart 'update-nix-daemon-store.service' to copy them." >&2
      fi

      exec nix daemon
    '';

  # This is the Nix base image used for the Nix Daemon.
  # The build script for the nixos/nix image is vendored due to Hydra limitations
  # cause fetching it is an IFD (Import from Derivation) which is not allowed.
  # Set `services.gitlab-runner-podman.nix-daemon.builder.enable = false` to
  # fetch `docker.nix` from the `NixOS/nix` repository instead.
  imageBaseFn =
    if cfg.nix-daemon.builder.enable then
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

  imageBase = pkgs.callPackage imageBaseFn {
    inherit (cfg.nix-daemon) nixConf;
    name = "local/nix-base";
    tag = "latest";
    bundleNixpkgs = false;
    maxLayers = 2;
  };

  # This is the daemon image which provides the store
  # as volumes.
  image = pkgs.dockerTools.buildLayeredImage {
    fromImage = imageBase;
    inherit (cfg.nix-daemon) name tag;

    inherit (cfg.nix-daemon) extraCommands;

    # Add all store paths and make them GC roots, so we dont loose them.
    # The GC roots only take effect once the paths are registered
    # (see `startScript`).
    # NOTE: Cannot add it to `extraPkgs` cause of the profile
    #       which uses `buildEnv` in the base image which collides.
    fakeRootCommands =
      # bash
      ''
        mkdir -p ".${storeRegistrationDir}"
        cp "${storeRegistration}/registration" \
           "${storeRegistration}/store-paths" \
           ".${storeRegistrationDir}/"

        mkdir -p nix/var/nix/gcroots/additional-pkgs
        ${lib.concatMapStringsSep "\n" (pkg: ''
          echo "Adding package '${pkg}'"
          ln -fs "${pkg}" "nix/var/nix/gcroots/additional-pkgs/"
        '') storePaths}
      ''
      + cfg.nix-daemon.fakeRootCommands;

    config = {
      Volumes = {
        "/nix/store" = { };
        "/nix/var/nix/db" = { };
        "/nix/var/nix/daemon-socket" = { };
      };
      Labels = cfg.images.noPruneLabels;
    }
    # Only set `Env` when configured, an empty list would drop the
    # environment inherited from the base image.
    // lib.optionalAttrs (cfg.nix-daemon.env != { }) {
      Env = lib.mapAttrsToList (k: v: "${k}=${v}") cfg.nix-daemon.env;
    };

    maxLayers = cfg.nix-daemon.maxLayers;
  };

  # The container for `virtualisation.oci-containers.containers`.
  container = {
    podman.user = cfg.ciUser.name;

    imageFile = image;
    image = "${cfg.nix-daemon.name}:${cfg.nix-daemon.tag}";

    volumes = [
      "${cfg.nix-daemon.volumes.store.name}:/nix/store"
      "${cfg.nix-daemon.volumes.db.name}:/nix/var/nix/db"
      "${cfg.nix-daemon.volumes.socket.name}:/nix/var/nix/daemon-socket"
      # TODO: Add signing key.
      # "${config.sops.secrets.nix-store-signing-key.path}:${config.sops.secrets.nix-store-signing-key.path}:ro"
    ];
    cmd = [
      "bash"
      "-c"
      startScript
    ];
  };

  # Script which copies all `storePaths` into the store volumes.
  updateStoreVolume = pkgs.callPackage ./scripts/copy-to-nix-store.nix {
    image = image.imageName + ":" + image.imageTag;
    imageDrv = image;
    volume-nix-store = cfg.nix-daemon.volumes.store.name;
    volume-nix-db = cfg.nix-daemon.volumes.db.name;
    nixStoreRegistrationDir = storeRegistrationDir;
  };
in
{
  inherit image container updateStoreVolume;
}
