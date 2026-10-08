{ lib, config, ... }:
let
  cfg = config.services.gitlab-runner-podman;
in
{
  users.users.${cfg.ciUser.name} = lib.mkIf (cfg.enable && cfg.ciUser.name != "root") {
    description = "CI user which runs all jobs over podman.";
    isNormalUser = true;

    inherit (cfg.ciUser) uid group;

    linger = true;
  };

  users.groups = {
    "${cfg.ciUser.group}" = {
      inherit (cfg.ciUser) gid;
    };
  };
}
