set positional-arguments
set shell := ["bash", "-cue"]
root_dir := `git rev-parse --show-toplevel`
flake_dir := root_dir
output_dir := root_dir / ".output"
build_dir := output_dir / "build"

mod nix "./tools/just/nix.just"
mod changelog "./tools/just/changelog.just"

# Default target if you do not specify a target.
default:
    just --list --unsorted

# Enter the default Nix development shell and execute the command `"$@`.
[group('general')]
develop *args:
    just nix::develop "default" "$@"

# Setup the project.
[group('general')]
setup *args:
    cd "{{root_dir}}" && ./tools/scripts/setup.sh

# Run commands over the ci development shell.
ci *args:
    just nix::develop "ci" "$@"

# Format the project.
[group('lint')]
format *args:
    nix run --accept-flake-config {{flake_dir}}#treefmt -- "$@"

# Lint the project.
[group('lint')]
lint *args:
    #!/usr/bin/env bash
    set -eu
    nix flake check --no-pure-eval

# Run the NixOS VM test.
[group('test')]
test type="test-gitlab-runner-unstable.driver" *args:
    #!/usr/bin/env bash
    set -eu
    just nix::run "{{type}}" "${@:2}"

# Run the NixOS VM test interactively.
[group('test')]
test-interactive *args:
    #! /usr/bin/env bash
    set -eu
    just test "test-gitlab-runner-unstable.driverInteractive" "$@"

# Run the example VM and drop into a shell.
[group('vm')]
test-vm *args:
    #! /usr/bin/env bash
    set -eu
    just nix::run "vm-example" "$@"

