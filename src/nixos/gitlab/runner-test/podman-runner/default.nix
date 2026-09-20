{ runnerConfig }:
{ lib, config, ... }:
let
  cfg = config.services.gitlab-runner-podman;
in
{
  services.gitlab-runner-podman.enable = true;

  # Define the Gitlab Runner.
  services.gitlab-runner.services.podman-runner = {
    description = runnerConfig.desc;

    registrationFlags = cfg.registrationFlags ++ [
      "--docker-pull-policy"
      "if-not-present"

      "--docker-allowed-pull-policies"
      "if-not-present"
    ];

    authenticationTokenConfigFile = runnerConfig.tokenFile;

    executor = "docker";
    dockerImage = cfg.jobs.defaultImageName;
    dockerAllowedImages = [ ];
    dockerPrivileged = false;
    requestConcurrency = 4;

    preBuildScript = "${lib.getExe cfg.preBuildScript}";
  };
}
