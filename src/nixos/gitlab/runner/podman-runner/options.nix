{ config, lib, ... }:
let
  cfg = config.services.gitlab-runner-podman;

  inherit (lib) mkOption mkEnableOption types;

  addOpts = maxL: {
    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };

    content = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };

    maxLayers = mkOption {
      type = types.number;
      default = maxL;
    };

    extraCommands = mkOption {
      type = types.str;
      default = "";
    };

    fakeRootCommands = mkOption {
      type = types.str;
      default = "";
    };
  };
in
{
  options.services.gitlab-runner-podman = {
    registrationFlags = mkOption {
      type = types.listOf types.str;
      readOnly = true;
    };

    preBuildScript = mkOption {
      type = types.package;
      readOnly = true;
    };

    volumes = {
      scratch = {
        name = mkOption {
          type = types.str;
          default = "gitlab-runner-podman-scratch";
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
      };
    };

    autoPrune = {
      enable = mkEnableOption "Enable auto pruning resources which do not have a label  `no-prune`";
    };

    nix-daemon = {
      name = mkOption {
        type = types.str;
        default = "local/nix-daemon";
      };
      tag = mkOption {
        type = types.str;
        default = "latest";
      };

      builder = {
        enable = mkEnableOption "Enable building the image over the given function.";
        func = mkOption {
          type = types.functionTo types.package;
          default = import ./nix-image.nix;
        };
      };

      version = mkOption {
        type = types.str;
        default = "2.34.7";
      };
      hash = mkOption {
        type = types.str;
        default = "sha256-8QYnRyGOTm3h/Dp8I6HCmQzlO7C009Odqyp28pTWgcY=";
      };

      volumes = {
        store = {
          name = mkOption {
            type = types.str;
            default = "nix-daemon-store";
          };
        };
        db = {
          name = mkOption {
            type = types.str;
            default = "nix-daemon-db";
          };
        };
        socket = {
          name = mkOption {
            type = types.str;
            default = "nix-daemon-socket";
          };
        };
      };

      nixConf = mkOption {
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
            };

            experimental-features = mkOption {
              type = types.listOf types.str;
              default = [
                "nix-command"
                "flakes"
              ];
            };

            # TODO: Make here a signing key.
            # secret-key-files = [ config.sops.secrets.nix-store-signing-key.path ];

            min-free = mkOption {
              type = types.str;
              default = "1G"; # Triggers garbage collection.
            };
            max-free = mkOption {
              type = types.str;
              default = "100G"; # Stops garbage collection at 100G free space.
            };
          };
        };
      };

      containerName = mkOption {
        type = types.str;
        default = "nix-daemon-container";
      };
    }
    // (addOpts 4);

    podman-daemon = {
      name = mkOption {
        type = types.str;
        default = "local/podman-daemon";
      };
      tag = mkOption {
        type = types.str;
        default = "latest";
      };

      imageName = mkOption {
        type = types.str;
        default = "quay.io/podman/stable";
      };
      imageDigest = mkOption {
        type = types.str;
        default = "sha256:7c9381b9af167cf2218831c3af3135856c99f488b543b78435c8f18e19ad739a";
      };
      hash = mkOption {
        type = types.str;
        default = "sha256-PLnPZxb0N/wnj5JCCx6gmxOfqkTasZFMedXykSjxxcs=";
      };

      volumes = {
        cache = {
          name = mkOption {
            type = types.str;
            default = "podman-daemon-cache";
          };
        };
        shared = {
          name = mkOption {
            type = types.str;
            default = "podman-daemon-shared";
          };
        };
        socket = {
          name = mkOption {
            type = types.str;
            default = "podman-daemon-socket";
          };
        };
      };

      containerName = mkOption {
        type = types.str;
        default = "podman-daemon-container";
      };
    };

    jobs = {
      defaultImageName = mkOption {
        type = types.str;
        default = "${cfg.jobs.alpine.name}:${cfg.jobs.alpine.tag}";
      };

      nix = {
        name = mkOption {
          type = types.str;
          default = "local/nix";
        };
        tag = mkOption {
          type = types.str;
          default = "latest";
        };

        containerName = mkOption {
          type = types.str;
          default = "job-nix-container";
        };
      }
      // (addOpts 3);

      alpine = {
        name = mkOption {
          type = types.str;
          default = "local/alpine";
        };
        tag = mkOption {
          type = types.str;
          default = "latest";
        };

        imageName = mkOption {
          type = types.str;
          default = "alpine";
        };
        imageDigest = mkOption {
          type = types.str;
          default = "sha256:beefdbd8a1da6d2915566fde36db9db0b524eb737fc57cd1367effd16dc0d06d";
        };
        hash = mkOption {
          type = types.str;
          default = "sha256-Sfb0quuaHgzxA7paz5P51WhdA35to39HtOufceXixz0=";
        };

        containerName = mkOption {
          type = types.str;
          default = "job-alpine-container";
        };
      }
      // (addOpts 3);

      ubuntu = {
        name = mkOption {
          type = types.str;
          default = "local/ubuntu";
        };
        tag = mkOption {
          type = types.str;
          default = "latest";
        };

        imageName = mkOption {
          type = types.str;
          default = "ubuntu";
        };
        imageDigest = mkOption {
          type = types.str;
          default = "sha256:1e622c5f073b4f6bfad6632f2616c7f59ef256e96fe78bf6a595d1dc4376ac02";
        };

        hash = mkOption {
          type = types.str;
          default = "sha256-aC8SgxdcMSaaU89YMr/uwE022Yqey2frmeZqr+L1xEU=";
        };

        containerName = mkOption {
          type = types.str;
          default = "job-ubuntu-container";
        };
      }
      // (addOpts 3);
    };
  };
}
