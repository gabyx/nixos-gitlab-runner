{ lib, ... }:
let
  inherit (lib) mkOption types;

  addOpts = {
    env = mkOption {
      type = types.attrsOf types.str;
      default = [ ];
    };

    content = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };

    maxLayers = mkOption {
      type = types.number;
      default = 3;
    };

    extraCommands = mkOption {
      type = types.str;
      default = null;
    };

    fakeRootCommands = mkOption {
      type = types.str;
      default = null;
    };
  };
in
{
  options.gitlab-podman-runner = {
    images = {
      noPruneLabels = mkOption {
        type = types.attrsOf types.str;
        default = {
          no-prune = "true";
        };
      };

      daemon = {
        builder = mkOption {
          type = types.function;
          default = null;
          examples = ''
            import ./nix-image.nix;
          '';
        };
        version = mkOption {
          type = types.str;
          default = "2.34.7";
        };
        hash = mkOption {
          type = types.str;
          default = "sha256-8QYnRyGOTm3h/Dp8I6HCmQzlO7C009Odqyp28pTWgcY=";
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
      };

      jobs = {
        nix = {
          name = mkOption {
            type = types.str;
            default = "local/nix";
          };
          tag = mkOption {
            type = types.str;
            default = "latest";
          };
        }
        // addOpts;

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
        }
        // addOpts;

        ubtuntu = {
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

        }
        // addOpts;
      };
    };
  };
}
