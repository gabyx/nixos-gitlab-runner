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

**Authors:**

- [Gabriel Nuetzi](mailto:647437+gabyx@users.noreply.github.com)

This repository provides production ready NixOS gitlab runner configurations.

> [!WARNING]
>
> The Gitlab runner tests are currently still maintained in nixpkgs. The goal is
> to take the more elaborate runner with the `podman-executor` out of nixpkgs
> and maintain it here as an example. This repository is currently in beta and
> should be upstreamed in the future to
> [https://github.com/nix-community](https://github.com/nix-community).

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

Acknowledge all contributors and external collaborators here.

## Copyright

Add here your copyright statement.
