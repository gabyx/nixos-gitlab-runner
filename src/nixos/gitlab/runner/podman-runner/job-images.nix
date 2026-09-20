{
  lib,
  pkgs,
  cfg,
}:
let
  # This derivation will contain a folder `/etc`
  files = pkgs.callPackage ./files { };
  initScripts = pkgs.callPackage ./scripts/init.nix { };
  preBuildScript = pkgs.callPackage ./scripts/prebuild.nix {
    profileScript = initScripts.profile;
  };

  toEnvList = envs: lib.mapAttrsToList (k: v: "${k}=${v}") envs;

  jobImagePkgs = [
    pkgs.nix
    pkgs.bash
    # Runtime dependencies of nix. (why I need to add these is not clear.)
    pkgs.gnutar
    pkgs.gzip
    pkgs.openssh
    pkgs.xz
    pkgs.cacert

    # Other stuff.
    pkgs.gnugrep # Gitlab Runner somehow needs this before prebuild script (?)

    preBuildScript

    files.containers
    files.commonRoot
  ]
  ++ cfg.jobs.defaultPackages;

  extraCommands =
    # bash
    ''
      set -eu -o pipefail
      # All created directories belong to root.

      # Set missing Nix directories.
      mkdir -p -m 0755 nix/var/log/nix/drvs
      mkdir -p -m 0755 nix/var/nix/{gcroots,profiles,temproots,userpool}
      mkdir -p -m 1777 nix/var/nix/{gcroots,profiles}/per-user
      mkdir -p -m 0755 nix/var/nix/profiles/per-user/root


      # Need a temporary dir.
      mkdir -p -m 1777 tmp

      # Root User
      mkdir -p root
      mkdir -p \
          root/.config/nix \
          root/.local/state \
          root/.local/share \
          root/.cache

      # Need a home dir.
      mkdir -p -m 0755 home

      # Copy some files from the store to make them writable.
      # - The passwd/group/nsswitch files from the /nix/store
      #   as podman otherwise has troubles with changing stuff
      #   and overmounting.
      #   Podman Error: creating temporary passwd file for container ...
      #          container open /var/lib/containers/storage/overlay/.../merged/nix/#        store/h95gjpn0n006pp5s9dkpdin386jbpv4p-basic-root-files/etc/group:
      #          no such file or directory
      # - We need to allow modification of nix config for cachix as
      #   otherwise it is link to the read only file in the store.
      filesToMakeWritable=(
        "etc/passwd" "etc/group" "etc/nsswitch.conf"
        "etc/nix/nix.conf"
      )
      for f in "''${filesToMakeWritable[@]}"; do
        if [ -L "$f" ]; then
          cp --no-preserve=all --remove-destination "$(readlink -f $f)" "$f"
        fi
      done
    '';

  fakeRootCommands =
    # bash
    ''
      # Create home.
      mkdir -p home/ci

      # Create XDG dirs.
      mkdir -p \
          home/ci/.config/nix \
          home/ci/.local/state \
          home/ci/.local/share \
          home/ci/.cache

      chown -R 1000:1000 home
    '';

  # Add some passthru attributes to the image derivations with
  # - the full image: full /nix/store
  # - the profile script
  # - the entrypoint script
  wrapWithStore =
    builder: attrs:
    let
      inner = builder attrs;
      innerFull = builder (attrs // { includeStorePaths = true; });
      res = inner.overrideAttrs (
        f: p: {
          # Some special attributes for separate inspection.
          passthru = {
            buildFull = innerFull;
            profileScript = initScripts.profile;
            entrypointScript = initScripts.entrypointScript;
          };
        }
      );
    in
    res;

  getFileInBase =
    imgConf: file:
    pkgs.writeShellScriptBin "get-file" ''
      ${lib.getExe pkgs.podman} run "${imgConf.imageName}@${imgConf.imageDigest}" \
      cat "${file}"
    '';

  envs = rec {
    common = {
      # Access to the nix daemon.
      NIX_REMOTE = "daemon";

      # Access to containerized podman.
      CONTAINER_HOST = "unix:///run/podman/podman.sock";

      PATH = "/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/sbin:/usr/bin:/usr/sbin";

      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

      # Make a fake nixpkgs which throws when using
      # `nix repl -f <nixpkgs>` for example.
      NIX_PATH = "nixpkgs=${files.fakeNixpkgs}";
    };

    nix = common // {
      IMAGE_OS_DIST = "nix";
    };

    alpine = common // {
      IMAGE_OS_DIST = "alpine";
    };

    ubuntu = common // {
      IMAGE_OS_DIST = "ubuntu";
    };
  };
in
{
  inherit preBuildScript;

  # All these packages are added to the Nix daemon.
  # which will end up in a `nix-daemon-store` volume.
  # The derivations which are taken out from the images
  # must be added here.
  allStoreDrv =
    jobImagePkgs
    ++ files.all
    ++ initScripts.all
    ++ cfg.jobs.nix.content
    ++ cfg.jobs.ubuntu.content
    ++ cfg.jobs.alpine.content;

  images = {
    # The Nix image.
    nix =
      let
        img = cfg.jobs.nix;
      in
      wrapWithStore pkgs.dockerTools.buildLayeredImage {
        inherit (img) name tag;

        extraCommands =
          extraCommands
          + ''
            set -eu -o pipefail
            # For `/usr/bin/env`.
            mkdir -p usr && ln -s ../bin usr/bin
          ''
          + img.extraCommands;

        fakeRootCommands = fakeRootCommands + img.fakeRootCommands;

        contents = jobImagePkgs ++ [ files.nixImage ] ++ img.content;
        # No store paths are copied into. We provide them by mounting the
        # /nix/store.
        includeStorePaths = false;

        config = {
          Labels = cfg.images.noPruneLabels;
          Env = toEnvList (envs.nix // img.env);
          Entrypoint = [ "${lib.getExe initScripts.entrypoint}" ];
        };

        inherit (img) maxLayers;
      };

    # This is the analog image to `local/nix` but alpine based.
    alpine =
      let
        img = cfg.jobs.alpine;

        # Update with:
        # ```shell
        # nix run "github:nixos/nixpkgs/nixos-unstable#nix-prefetch-docker" -- --image-name alpine --image-tag latest
        # nix run ".#nixosConfigurations.gitlab-runner.config.virtualisation.oci-containers.containers.alpine-container.imageFile.originalPasswd"
        # ```
        imgConf = {
          inherit (img) imageName imageDigest hash;
          finalImageName = img.imageName;
          finalImageTag = "latest";
        };
        alpineBase = pkgs.dockerTools.pullImage imgConf;
      in
      (wrapWithStore pkgs.dockerTools.buildLayeredImage {
        fromImage = alpineBase;
        inherit (img) name tag;

        extraCommands = extraCommands + img.extraCommands;
        fakeRootCommands = fakeRootCommands + img.fakeRootCommands;

        contents = jobImagePkgs ++ [ files.alpineImage ] ++ img.content;
        # No store paths are copied into. We provide them by mounting the
        # /nix/store.
        includeStorePaths = false;

        config = {
          Labels = cfg.images.noPruneLabels;
          Env = toEnvList (envs.alpine // img.env);
          Entrypoint = [ "${lib.getExe initScripts.entrypoint}" ];
        };

        # Only if `build buildLayeredImage`.
        inherit (img) maxLayers;
      }).overrideAttrs
        (
          f: p: {
            passthru = p.passthru // {
              originalPasswd = getFileInBase imgConf "/etc/passwd";
              originalGroup = getFileInBase imgConf "/etc/group";
            };
          }
        );

    # This is the analog image to `local/nix` but ubuntu based.
    ubuntu =
      let
        img = cfg.jobs.ubuntu;

        # Update with:
        # ```shell
        # nix run "github:nixos/nixpkgs/nixos-unstable#nix-prefetch-docker" -- \
        #   --image-name ubuntu --image-tag latest
        # nix run ".#nixosConfigurations.gitlab-runner.config.virtualisation.oci-containers.containers.ubuntu-container.imageFile.originalPasswd"
        # ```
        imgConf = {
          inherit (img) imageName imageDigest hash;
          finalImageName = img.imageName;
          finalImageTag = "latest";
        };
        ubuntuBase = pkgs.dockerTools.pullImage imgConf;
      in
      (wrapWithStore pkgs.dockerTools.buildLayeredImage {
        fromImage = ubuntuBase;
        inherit (img) name tag;

        extraCommands = extraCommands + img.extraCommands;
        fakeRootCommands = fakeRootCommands + img.fakeRootCommands;

        contents = jobImagePkgs ++ [ files.ubuntuImage ] ++ img.content;
        # No store paths are copied into. We provide them by mounting the
        # /nix/store.
        includeStorePaths = false;

        config = {
          Labels = cfg.images.noPruneLabels;
          Env = toEnvList (envs.ubuntu // img.env);
          Entrypoint = [ "${lib.getExe initScripts.entrypoint}" ];
        };

        # Only if `build buildLayeredImage`.
        inherit (img) maxLayers;
      }).overrideAttrs
        (
          f: p: {
            passthru = p.passthru // {
              originalPasswd = getFileInBase imgConf "/etc/passwd";
              originalGroup = getFileInBase imgConf "/etc/group";
            };
          }
        );
  };
}
