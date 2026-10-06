# Wrapper around `config.system.build.vm` which keeps all mutable VM state
# (disk image and runner token) in one directory and seeds a placeholder token,
# such that `nix run .#example-vm` works out of the box.
{
  lib,
  coreutils,
  writeShellApplication,
  writeText,
  vm,
}:
let
  placeholderToken = writeText "gitlab-runner-token.env" ''
    # Runner authentication token. Create a runner in the Gitlab web interface
    # ("Settings -> CI/CD -> Runners -> New instance runner"), paste its token
    # below and restart the VM.
    CI_SERVER_URL=https://gitlab.com
    CI_SERVER_TOKEN=glrt-REPLACE-ME
  '';
in
writeShellApplication {
  name = "example-vm";

  runtimeInputs = [ coreutils ];

  text = ''
    state_dir="''${EXAMPLE_VM_STATE_DIR:-$PWD/.output/state/example-vm}"
    secrets_dir="''${GITLAB_RUNNER_SECRETS_DIR:-$state_dir/secrets}"
    token_file="$secrets_dir/token.env"

    mkdir -p "$secrets_dir"

    if [ ! -e "$token_file" ]; then
      install -m 0600 "${placeholderToken}" "$token_file"

      echo "Wrote a placeholder runner token to:" >&2
      echo "  $token_file" >&2
      echo "The runner does not register until a real token is in it." >&2
    fi

    export GITLAB_RUNNER_SECRETS_DIR="$secrets_dir"

    NIX_DISK_IMAGE="''${NIX_DISK_IMAGE:-$state_dir/disk.qcow2}"
    export NIX_DISK_IMAGE

    echo "VM state directory: $state_dir" >&2
    echo "Login as 'root' (password 'root'), quit the VM with 'Ctrl-a x'." >&2

    exec ${lib.getExe vm} "$@"
  '';

  meta = {
    description = "Run the Gitlab runner example NixOS VM";
    mainProgram = "example-vm";
  };
}
