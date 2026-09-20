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

## Documentation

## Executor: `podman`

The [`podman-executor`](./src/nixos/gitlab/runner/podman-runner) gives a **more
elaborate** example how to configure a Gitlab Runner with caching and reasonably
good security practices.

The [VM tested `podman-runner`](./src/nixos/gitlab/runner/podman-runner) (a
NixOS module for reuse) configures an advanced Gitlab runner with the following
features:

- The executor is `podman` which gives you better additional safety than
  `docker`. That means every job is run in a `podman` container.

- The following container **images** are built with Nix:

  **Container Images for Gitlab Jobs**:
  - `local/alpine`: An image based on Alpine with a Nix installation (attribute
    `jobImages.alpine`).
  - `local/ubuntu`: An image based on Ubuntu with a Nix installation (attribute
    `jobImages.ubuntu`).
  - `local/nix`: An image based on Nix which only comes with `nix` installed
    (attribute `jobImages.nix`).

  **Images for VM Setup**:
  - `local/nix-daemon-image`: An image with a Nix daemon which is used to share
    the `/nix/store` across jobs (variable `nixDaemonImage`) setup with some
    essentials derivations `bootstrapPkgs`.
  - `local/podman-daemon-image`: An image with `podman` running as a daemon
    which is used to run `podman` inside the above job containers images
    (variable `podmanDaemonImage`).

- Every job container runs in a `podman` container instance based by default on
  `jobImage.ubuntu`. A pipeline job can override this with
  `image: local/alpine`.
  - Each job container will have the `/nix/store` mounted from the container
    `nix-daemon-container` (see registration flags
    `--docker-volumes-from "nix-daemon-container:ro"`).

    The `nix-daemon-container` is a single container instance of a
    `nixDaemonImage`. This enables caching of `/nix/store` paths across all jobs
    in **all** runners. This makes **the host VM's `/nix/store` independent of
    the Nix store used in the jobs**, which is good.

    ::: {.note} **Security:** If you don't want this you need multiple
    `nixDaemonImage` containers for each registered runner
    (`gitlab-runner.services.<name>`). :::

  - Each job container will have the `/run/podman/podman.sock` socket mounted
    from the `podman-daemon-container`.

    The `podman-daemon-container` is a single container of a `podmanDaemonImage`
    which runs `podman` as a daemon. Job containers can use this daemon to spawn
    nested containers as well (podman-in-podman). **Keep in mind that `bind`
    mounts are local to the `podman-daemon-container`** and can be be worked
    around with a `podman volume create <vol>` and manual copy-to/copy-from this
    volume `<vol>`.

    If you only need to build containers you don't need this feature
    (`podman-daemon-container`), see below point.

    Container configuration files (`auxRootFiles`) are copied to all containers
    to ensure `podman` works consistently inside the job containers.

  - The job containers do **not** mount the `podman` socket from the host (NixOS
    VM) mounted for security reasons.

    ::: {.note} Building container images with `buildah` (stripped `podman` for
    building images) inside a job which runs `jobImage.alpine` is still
    possible. :::

  - **Cleanup Disk Space**:

    With this setup its really easy to clean the `nix-daemon-container` (e.g. if
    you run out of disk space), then reboot and have the runner in a clean
    state. You can do the following to effectively clean everything and start
    with fresh volumes safely:

    ```bash
    # Stop the Gitlab runner.
    systemctl stop gitlab-runner.service
    # Stop `systemd`-managed containers, such that they get not recreated
    # when deleting below.
    systemctl stop podman-podman-daemon-container.service \
                  podman-nix-daemon-container.service \
                  podman-nix-container.service \
                  podman-alpine-container.service \
                  podman-ubuntu-container.service || true

    podman container rm -f --all
    podman image rm -f --all
    podman volumes rm -f --all

    reboot
    # Systemd will restart all containers and create volumes etc.
    ```

:::

## Example

TODO

## Tests

The Gitlabe CI runner NixOS VM tests can be run with for
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
