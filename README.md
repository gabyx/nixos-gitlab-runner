<p align="center">
  <img src="./docs/assets/logo.svg" alt="project logo" width="250">
</p>

<h1 align="center">
  NixOS Gitlab Runner Configurations
</h1>
<p align="center">
</p>

[![Current Release](https://img.shields.io/github/release/gabyx/nixos-gitlab-runner.svg?label=release)](https://github.com/gabyx/nixos-gitlab-runner/releases/latest)
[![Pipeline Status](https://img.shields.io/github/actions/workflow/status/gabyx/nixos-gitlab-runner/normal.yaml?label=ci)](https://github.com/gabyx/nixos-gitlab-runner/actions/workflows/normal.yaml)
[![License label](https://img.shields.io/badge/License-MIT-blue.svg?)](https://mit-license.org/)

**This repository provides production ready NixOS gitlab runner
configurations.**

> [!WARNING]
>
> The Gitlab runner tests & documentation are currently still maintained in
> nixpkgs. The goal is to take the more elaborate runner with the
> `podman-executor` out of nixpkgs and maintain it here as an example. This
> repository is currently in beta and should be upstreamed in the future to
> [https://github.com/nix-community](https://github.com/nix-community).

> [!NOTE]
>
> The Gitlab runner configuration
> [podman-executor](src/nixos/gitlab/runner/podman-runner/default.nix) is
> already used in production and works.

## Usage

In a NixOS configuration do:

```nix
{config, ...}:
let
  cfg = config.services.gitlab-runner-podman;
in
{
  # Import the NixOS module.
  import = [ inputs.nixos-gitlab-runner.nixosModules.gitlab-runner-podman ];

  # Enable it.
  services.gitlab-runner-podman.enable = true;

  # Define a runner.
  # See: https://search.nixos.org/options?channel=26.05&query=gitlab-runner&type=options#show=option%253Aservices.gitlab-runner.services.%253Cname%253E.registrationConfigFile
  services.gitlab-runner.services.nix-runner = {
    description = "nix-runner"

    registrationFlags = cfg.registrationFlags ++ [
      "--docker-pull-policy"
      "if-not-present"

      "--docker-allowed-pull-policies"
      "if-not-present"
    ];

    # Get this on the Gitlab web interface by adding a new runner.
    authenticationTokenConfigFile = "<gitlab-registration-token>";

    executor = "docker";
    dockerImage = cfg.jobs.defaultImageName;
    dockerAllowedImages = [ ];
    dockerPrivileged = false;
    requestConcurrency = 4;

    preBuildScript = "${lib.getExe cfg.preBuildScript}";
  }
}
```

## The `podman` Executor

The [`podman-executor`](./src/nixos/gitlab/runner/podman-runner) NixOS module
gives a **more elaborate** example how to configure a Gitlab Runner with caching
and reasonably good security practices with the below features. The NixOs module
is configured under `services.gitlab-runner-podman` (abbrev. to `cfg`):

- The executor is `podman` which gives you better additional safety than
  `docker`. That means every job is run in a `podman` container.

### Images

The following container **images** are built with Nix:

#### Container Images for Gitlab Jobs

- `local/alpine`: An image based on Alpine with a Nix installation (settings
  `cfg.jobs.alpine`).

- `local/ubuntu`: An image based on Ubuntu with a Nix installation (settings
  `cfg.jobs.ubuntu`).

- `local/nix`: An image based on Nix which only comes with `nix` installed
  (settings `cfg.jobs.nix`).

##### Entrypoint

Each job image contains **two users**:

- `root` (uid `0`, home `/root`): the user a job runs as by default.
- `ci` (uid `1000`, group `ci`, home `/home/ci`): an unprivileged user to run
  the job's commands as, see `CONTAINER_USERSPEC` below.

Each job image uses the same **entrypoint script**
([`scripts/init.nix`](./src/nixos/gitlab/runner/podman-runner/scripts/init.nix))
which must run as `root` and does the following:

- It reads a user specification of the form `UID:GID` (e.g. `ci:ci`) from the
  environment variable `CONTAINER_USERSPEC` and unsets it, such that nested
  containers do not inherit it.

- It aborts when the container was not started as `root` while `CI=true` (and
  only warns otherwise): running as another user circumvents the entrypoint and
  the setup below.

- When `CONTAINER_USERSPEC` is set, it `chown`s `$CI_PROJECT_DIR` recursively to
  that user and group and then re-executes the command with `gosu` as that user.
  Otherwise the command runs as `root`.

- Before executing the command it sources the profile script which exports
  `USER` and `HOME` (`/root` or `/home/<user>`), sources Nix's `nix-daemon.sh`
  (which sets up the Nix profile and `PATH`) and exports the `XDG_*`
  directories. Sourcing it twice is a no-op (`__USER_PROFILE_SOURCED`).

  The same profile script is sourced by the pre-build script
  (`cfg.preBuildScript`), such that a job gets this environment over both paths.

- All output of the entrypoint goes to `stderr`, such that capturing the
  `stdout` of a job command stays free of it.

#### Images for CI Setup

- `local/nix-daemon`: An image with a Nix daemon which is used to share the
  `/nix/store` across jobs (settings `cfg.nix-daemon`) setup with all essential
  derivations of the job images.

- `local/podman-daemon`: An image with `podman` running as a daemon which is
  used to run `podman` inside the above job containers images (settings
  `cfg.podman-daemon`).

#### Job Containers

- Every job container runs in a `podman` container instance based by default on
  `local/alpine` (setting `cfg.jobs.defaultImageName`). A pipeline job can
  override this with `image: local/ubuntu`.

  - Each job container will have the `/nix/store` mounted from the container
    `nix-daemon-container` (see registration flags
    `--docker-volumes-from "nix-daemon-container:ro"`).

    The `nix-daemon-container` (settings `cfg.nix-daemon`) is a single container
    instance of `local/nix-daemon`. This enables caching of `/nix/store` paths
    across all jobs in **all** runners. This makes **the host VM's `/nix/store`
    independent of the Nix store used in the jobs**, which is good.

> [!NOTE]
>
> **Security:** If you don't want this you need multiple `local/nix-daemon`
> containers for each registered runner (`gitlab-runner.services.<name>`).

#### Podman inside Job Container

- Each job container will have the `/run/podman/podman.sock` socket mounted from
  the `podman-daemon-container` (settings `cfg.podman-daemon`).

  The `podman-daemon-container` is a single container of `local/podman-daemon`
  which runs `podman` as a daemon. Job containers can use this daemon to spawn
  nested containers as well (podman-in-podman). **Keep in mind that `bind`
  mounts are local to the `podman-daemon-container`** and can be be worked
  around with a `podman volume create <vol>` and manual copy-to/copy-from this
  volume `<vol>`.

  If you only need to build containers you don't need this feature
  (`podman-daemon-container`), see below point.

  Container configuration files (`files/containers`) are copied to all
  containers to ensure `podman` works consistently inside the job containers.

- The job containers do **not** mount the `podman` socket from the host (NixOS
  VM) mounted for security reasons.

  > [!NOTE]
  >
  > Building container images with `buildah` (stripped `podman` for building
  > images) inside a job which runs `local/alpine` is still possible.

#### Cleanup Disk Space

With this setup its really easy to clean the `nix-daemon-container` (e.g. if you
run out of disk space), then reboot and have the runner in a clean state. You
can do the following to effectively clean everything and start with fresh
volumes safely:

```bash
# Stop the Gitlab runner.
systemctl stop gitlab-runner.service
# Stop `systemd`-managed containers, such that they get not recreated
# when deleting below.
systemctl stop podman-podman-daemon-container.service \
              podman-nix-daemon-container.service \
              podman-job-nix-container.service \
              podman-job-alpine-container.service \
              podman-job-ubuntu-container.service || true

podman container rm -f --all
podman image rm -f --all
podman volume rm -f --all

reboot
# Systemd will restart all containers and create volumes etc.
```

## Example

TODO

## Tests

The Gitlab CI runner NixOS VM tests can be run with for
[mvs](https://github.com/fzakaria/nixpkgs-multiverse) pinned `nixos-unstable`
and pinned `nixos-26.05` with

```bash
just test "test-gitlab-runner-unstable"
just test "test-gitlab-runner-2605"
```

## Development

Read first the [Contribution Guidelines](/CONTRIBUTING.md).

For technical documentation on setup and development, see the
[Development Guide](docs/development-guide.md)

## Acknowledgement

- [SDSC Zurich](www.datascience.ch)
- The Gitlab
  [maintainer team in nixpkgs](https://github.com/NixOS/nixpkgs/blob/master/maintainers/team-list.nix).
- The [Nix Community](https://discourse.nixos.org)
