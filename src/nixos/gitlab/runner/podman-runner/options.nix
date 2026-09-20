{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gitlab-runner-podman;

  inherit (lib) mkOption mkEnableOption types;

  # Options which every image built by this module shares.
  addOpts = what: maxL: {
    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        CARGO_HOME = "/scratch/cargo";
      };
      description = ''
        Additional environment variables baked into the ${what} image.

        These are merged over the variables this module sets itself, so they
        can be used to override defaults such as `NIX_REMOTE` or `PATH`.
      '';
    };

    content = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.rustup pkgs.jq ]";
      description = ''
        Additional packages added to the contents of the ${what} image.

        The job images carry no store paths themselves (they mount the store
        of the Nix daemon container), therefore every package listed here is
        also registered as a garbage collector root inside the Nix daemon
        image, such that it survives a garbage collection.
      '';
    };

    maxLayers = mkOption {
      type = types.ints.positive;
      default = maxL;
      description = ''
        Maximum number of layers of the ${what} image, see `maxLayers` of
        {nix}`pkgs.dockerTools.buildLayeredImage`.
      '';
    };

    extraCommands = mkOption {
      type = types.str;
      default = "";
      example = "mkdir -p ./opt/my-tool";
      description = ''
        Extra shell commands appended to `extraCommands` of the ${what}
        image. They run **unprivileged** in the image root directory before
        the layer is created.
      '';
    };

    fakeRootCommands = mkOption {
      type = types.str;
      default = "";
      example = "chown -R 1000:1000 ./opt";
      description = ''
        Extra shell commands appended to `fakeRootCommands` of the ${what}
        image. They run inside `fakeroot`, so they may change ownership and
        permissions.
      '';
    };
  };
in
{
  options.services.gitlab-runner-podman = {
    enable = mkEnableOption ''
      the podman image setup for job images, nix daemon, podman daemon for different gitlab runners to configure over {option}`services.gitlab-runner.services.<name>`
    '';

    registrationFlags = mkOption {
      type = types.nullOr (types.listOf types.str);
      apply =
        v:
        assert lib.assertMsg cfg.enable
          "You must enable the module `service.gitlab-runner-podman` before using this option.";
        v;
      readOnly = true;
      description = ''
        Registration flags computed by this module, to be passed to
        {option}`services.gitlab-runner.services.<name>.registrationFlags`.

        They wire a job container to the scratch volume, to the podman
        daemon socket and to the read-only Nix store of the Nix daemon
        container. This option is read-only, append own flags at the use
        site.
      '';
    };

    preBuildScript = mkOption {
      type = types.package;
      apply =
        v:
        assert lib.assertMsg cfg.enable
          "You must enable the module `service.gitlab-runner-podman` before using this option.";
        v;
      readOnly = true;
      description = ''
        The pre-build script computed by this module, to be passed to
        {option}`services.gitlab-runner.services.<name>.preBuildScript`.

        It sets up the Nix profile and the per-pipeline scratch directory
        `/scratch/$CI_PIPELINE_ID` inside the job container.
      '';
    };

    volumes = {
      scratch = {
        name = mkOption {
          type = types.str;
          default = "gitlab-runner-podman-scratch";
          description = ''
            Name of the podman volume mounted at `/scratch` in every job
            container. The pre-build script creates a per-pipeline directory
            in it and exports it as `CI_CUSTOM_SCRATCH_DIR`.
          '';
        };
      };
    };

    images = {
      noPruneLabels = mkOption {
        type = types.attrsOf types.str;
        default = {
          no-prune = "true";
        };
        readOnly = true;
        description = ''
          Labels applied to every image built by this module. They keep the
          images out of the automatic prune (see {option}`autoPrune.enable`).
        '';
      };
    };

    autoPrune = {
      enable = mkEnableOption ''
        periodic pruning of all containers, images and volumes which are not
        labeled `no-prune`. The images built by this module carry that
        label and are therefore kept
      '';
    };

    nix-daemon = {
      name = mkOption {
        type = types.str;
        default = "local/nix-daemon";
        description = ''
          Image name of the Nix daemon image. This image runs `nix daemon`
          and shares its `/nix/store` with all job containers, which makes
          the Nix store of the jobs independent of the host's one.
        '';
      };
      tag = mkOption {
        type = types.str;
        default = "latest";
        description = "Image tag of the Nix daemon image.";
      };

      builder = {
        enable =
          mkOption {
            type = types.bool;
            default = false;
            description = ''
              building the Nix base image with the function in
              {option}`services.gitlab-runner-podman.nix-daemon.builder.func`
              instead of fetching `docker.nix` from the `NixOS/nix` repository.

              Keep this enabled (the default) when the result must be
              buildable by Hydra: fetching `docker.nix` is an import from
              derivation (IFD) which Hydra refuses
            '';
          }
          // {
            default = true;
          };

        func = mkOption {
          type = types.functionTo types.package;
          default = import ./nix-image.nix;
          defaultText = lib.literalExpression "import ./nix-image.nix";
          description = ''
            Function building the Nix base image, called with
            {nix}`pkgs.callPackage`. The default is the vendored copy of
            `docker.nix` from the `NixOS/nix` repository.

            Only used when {option}`builder.enable` is `true`.
          '';
        };
      };

      version = mkOption {
        type = types.str;
        default = "2.34.7";
        description = ''
          Git revision of the `NixOS/nix` repository to take `docker.nix`
          from. Only used when {option}`builder.enable` is `false`.
        '';
      };
      hash = mkOption {
        type = types.str;
        default = "sha256-8QYnRyGOTm3h/Dp8I6HCmQzlO7C009Odqyp28pTWgcY=";
        description = ''
          Hash of the `NixOS/nix` source tree fetched for
          {option}`version`, must be updated together with it. Only used
          when {option}`builder.enable` is `false`.
        '';
      };

      volumes = {
        store = {
          name = mkOption {
            type = types.str;
            default = "nix-daemon-store";
            description = ''
              Name of the podman volume holding `/nix/store` of the Nix
              daemon. It is mounted read-only into every job container and
              is the shared build cache over all jobs and runners.

              Deleting it is safe: the `update-nix-daemon-store` service
              repopulates it from the image on the next start.
            '';
          };
        };
        db = {
          name = mkOption {
            type = types.str;
            default = "nix-daemon-db";
            description = ''
              Name of the podman volume holding `/nix/var/nix/db`, the Nix
              database belonging to {option}`volumes.store.name`. Delete it
              only together with the store volume, never on its own.
            '';
          };
        };
        socket = {
          name = mkOption {
            type = types.str;
            default = "nix-daemon-socket";
            description = ''
              Name of the podman volume holding
              `/nix/var/nix/daemon-socket` over which the job containers
              talk to the Nix daemon (`NIX_REMOTE=daemon`).
            '';
          };
        };
      };

      nixConf = mkOption {
        description = ''
          Contents of `/etc/nix/nix.conf` inside the Nix daemon image.

          This is a freeform option: every setting which is not listed below
          is passed through to `nix.conf` verbatim.
        '';
        type = types.submodule {
          freeformType = types.attrsOf (
            types.nullOr (
              types.oneOf [
                types.str
                (types.listOf types.str)
              ]
            )
          );

          options = {
            cores = mkOption {
              type = types.str;
              default = "0";
              description = ''
                Value of the `cores` setting, `0` lets Nix use all available
                cores of the runner host.
              '';
            };

            experimental-features = mkOption {
              type = types.listOf types.str;
              default = [
                "nix-command"
                "flakes"
              ];
              description = "Value of the `experimental-features` setting.";
            };

            # TODO: Make here a signing key.
            # secret-key-files = [ config.sops.secrets.nix-store-signing-key.path ];

            min-free = mkOption {
              type = types.str;
              default = "1G";
              description = ''
                Value of the `min-free` setting: the free disk space below
                which the daemon starts collecting garbage.
              '';
            };
            max-free = mkOption {
              type = types.str;
              default = "100G";
              description = ''
                Value of the `max-free` setting: the free disk space at
                which the daemon stops collecting garbage again.
              '';
            };
          };
        };
      };

      containerName = mkOption {
        type = types.str;
        default = "nix-daemon-container";
        description = ''
          Name of the podman container running the Nix daemon. It also
          determines the systemd unit name (`podman-<name>.service`) and is
          used in the `--docker-volumes-from` registration flag with which
          the job containers mount its Nix store.
        '';
      };
    }
    // (addOpts "Nix daemon" 4);

    podman-daemon = {
      name = mkOption {
        type = types.str;
        default = "local/podman-daemon";
        description = ''
          Image name of the podman daemon image. This image runs
          `podman system service` such that jobs can start nested containers
          without access to the podman socket of the host.
        '';
      };
      tag = mkOption {
        type = types.str;
        default = "latest";
        description = "Image tag of the podman daemon image.";
      };

      imageName = mkOption {
        type = types.str;
        default = "quay.io/podman/stable";
        description = "Name of the base image the podman daemon image is built from.";
      };
      imageDigest = mkOption {
        type = types.str;
        default = "sha256:7c9381b9af167cf2218831c3af3135856c99f488b543b78435c8f18e19ad739a";
        description = ''
          Digest of the base image {option}`imageName`, update it together
          with {option}`hash`:

          ```shell
          nix run "github:nixos/nixpkgs/nixos-unstable#nix-prefetch-docker" -- \
            --image-name quay.io/podman/stable --image-tag v5.6.0
          ```
        '';
      };
      hash = mkOption {
        type = types.str;
        default = "sha256-PLnPZxb0N/wnj5JCCx6gmxOfqkTasZFMedXykSjxxcs=";
        description = ''
          Hash of the pulled base image {option}`imageDigest`, must be
          updated together with it.

          Note that this hash also covers the tag under which the image is
          stored locally, which is `latest` and not the upstream release tag
          printed by `nix-prefetch-docker`.
        '';
      };

      volumes = {
        cache = {
          name = mkOption {
            type = types.str;
            default = "podman-daemon-cache";
            description = ''
              Name of the podman volume holding the container storage
              `/var/lib/container` of the podman daemon, i.e. the image
              cache for nested containers.
            '';
          };
        };
        shared = {
          name = mkOption {
            type = types.str;
            default = "podman-daemon-shared";
            description = ''
              Name of the podman volume mounted read-only at
              `/var/lib/shared` for additional shared image stores.
              Currently not needed.
            '';
          };
        };
        socket = {
          name = mkOption {
            type = types.str;
            default = "podman-daemon-socket";
            description = ''
              Name of the podman volume holding the socket directory
              `/run/podman` of the podman daemon. It is mounted into every
              job container which reaches it over
              `CONTAINER_HOST=unix:///run/podman/podman.sock`.

              Keep in mind that `bind` mount paths made over this socket are
              local to the podman daemon container, not to the job!
              So the only sane way is to use volume mounts when using `podman`
              inside a job container.
            '';
          };
        };
      };

      containerName = mkOption {
        type = types.str;
        default = "podman-daemon-container";
        description = ''
          Name of the podman container running the podman daemon. It also
          determines the systemd unit name (`podman-<name>.service`).
        '';
      };
    };

    jobs = {
      defaultPackages = mkOption {
        type = types.listOf types.package;
        description = ''
          The default packages in every job container.
          These live in the `nix-daemon`'s `/nix/store` and only symlinks are maintained in
          the job containers to make them small.
        '';
        default = [
          (lib.hiPrio pkgs.coreutils)
          (lib.hiPrio pkgs.findutils)
          pkgs.openssh
          pkgs.bashInteractive
          (lib.hiPrio pkgs.git)

          pkgs.cachix # For cachix.org.

          pkgs.podman # For nested containers.
        ];
      };

      defaultImageName = mkOption {
        type = types.str;
        default = "${cfg.jobs.alpine.name}:${cfg.jobs.alpine.tag}";
        defaultText = lib.literalExpression ''"''${cfg.jobs.alpine.name}:''${cfg.jobs.alpine.tag}"'';
        description = ''
          Image a job runs in when its pipeline does not specify one, to be
          passed to
          {option}`services.gitlab-runner.services.<name>.dockerImage`. A
          pipeline job can override it with `image: local/ubuntu`.
        '';
      };

      nix = {
        name = mkOption {
          type = types.str;
          default = "local/nix";
          description = ''
            Image name of the `nix` job image which only comes with `nix`
            installed and no other distribution userland.
          '';
        };
        tag = mkOption {
          type = types.str;
          default = "latest";
          description = "Image tag of the `nix` job image.";
        };

        containerName = mkOption {
          type = types.str;
          default = "job-nix-container";
          description = ''
            Name of the podman container which registers the `nix` job image
            in the local image store. It runs once and exits, it is not the
            container a job runs in.
          '';
        };
      }
      // (addOpts "`nix` job" 3);

      alpine = {
        name = mkOption {
          type = types.str;
          default = "local/alpine";
          description = ''
            Image name of the `alpine` job image, an Alpine userland with a
            Nix installation.
          '';
        };
        tag = mkOption {
          type = types.str;
          default = "latest";
          description = "Image tag of the `alpine` job image.";
        };

        imageName = mkOption {
          type = types.str;
          default = "alpine";
          description = "Name of the base image the `alpine` job image is built from.";
        };
        imageDigest = mkOption {
          type = types.str;
          default = "sha256:beefdbd8a1da6d2915566fde36db9db0b524eb737fc57cd1367effd16dc0d06d";
          description = ''
            Digest of the base image {option}`imageName`, update it together
            with {option}`hash`:

            ```shell
            nix run "github:nixos/nixpkgs/nixos-unstable#nix-prefetch-docker" -- \
              --image-name alpine --image-tag latest
            ```
          '';
        };
        hash = mkOption {
          type = types.str;
          default = "sha256-Sfb0quuaHgzxA7paz5P51WhdA35to39HtOufceXixz0=";
          description = ''
            Hash of the pulled base image {option}`imageDigest`, must be
            updated together with it.
          '';
        };

        containerName = mkOption {
          type = types.str;
          default = "job-alpine-container";
          description = ''
            Name of the podman container which registers the `alpine` job
            image in the local image store. It runs once and exits, it is
            not the container a job runs in.
          '';
        };
      }
      // (addOpts "`alpine` job" 3);

      ubuntu = {
        name = mkOption {
          type = types.str;
          default = "local/ubuntu";
          description = ''
            Image name of the `ubuntu` job image, an Ubuntu userland with a
            Nix installation.
          '';
        };
        tag = mkOption {
          type = types.str;
          default = "latest";
          description = "Image tag of the `ubuntu` job image.";
        };

        imageName = mkOption {
          type = types.str;
          default = "ubuntu";
          description = "Name of the base image the `ubuntu` job image is built from.";
        };
        imageDigest = mkOption {
          type = types.str;
          default = "sha256:1e622c5f073b4f6bfad6632f2616c7f59ef256e96fe78bf6a595d1dc4376ac02";
          description = ''
            Digest of the base image {option}`imageName`, update it together
            with {option}`hash`:

            ```shell
            nix run "github:nixos/nixpkgs/nixos-unstable#nix-prefetch-docker" -- \
              --image-name ubuntu --image-tag latest
            ```

            The `/etc/passwd` and `/etc/group` in `files/ubuntu-image` are
            taken from this base image and must be refreshed with it:

            ```shell
            nix run ".#nixosConfigurations.gitlab-runner.config.virtualisation.oci-containers.containers.job-ubuntu-container.imageFile.originalPasswd"
            ```
          '';
        };

        hash = mkOption {
          type = types.str;
          default = "sha256-aC8SgxdcMSaaU89YMr/uwE022Yqey2frmeZqr+L1xEU=";
          description = ''
            Hash of the pulled base image {option}`imageDigest`, must be
            updated together with it.
          '';
        };

        containerName = mkOption {
          type = types.str;
          default = "job-ubuntu-container";
          description = ''
            Name of the podman container which registers the `ubuntu` job
            image in the local image store. It runs once and exits, it is
            not the container a job runs in.
          '';
        };
      }
      // (addOpts "`ubuntu` job" 3);
    };
  };
}
