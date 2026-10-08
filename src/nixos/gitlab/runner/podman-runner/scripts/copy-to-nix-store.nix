# Script to copy all derivations from a podman `image`
# to the nix store in volume `volume-nix-store` and update the `volume-nix-db`.
{
  writeShellApplication,
  podman,
  coreutils,
  imageDrv,
  image,
  volume-nix-store,
  volume-nix-db,
}:
writeShellApplication {
  name = "gitlab-runner-copy-to-nix-store";

  runtimeInputs = [
    podman
    coreutils
  ];

  text = # bash
    ''
      set -e
      set -u

      for vol in "${volume-nix-store}" "${volume-nix-db}"; do
        if ! podman volume inspect "$vol" >/dev/null; then
          echo "No '$vol' volume found -> Skip copy derivations to ${volume-nix-store}." >&2
          exit 0
        fi
      done

      if ! podman image inspect "${image}"; then
        echo "Image not know, load it." >&2
        podman load -i "${imageDrv}"
      fi

      CMD=$(
          cat <<"EOF"
      # Get all store paths.
      readarray -t DRVS < <(nix-store --gc --print-roots | cut -d ' ' -f 3)

      nix --extra-experimental-features nix-command copy --no-check-sigs --to /nix-custom "''${DRVS[@]}"
      EOF
      )

      echo "Podman images:"
      podman images

      echo "Copy pkgs to '${volume-nix-store}' from '${image}'."
      podman run --rm \
          -v "${volume-nix-store}:/nix-custom/nix/store" \
          -v "${volume-nix-db}:/nix-custom/nix/var/nix/db" \
          "${image}" \
          bash -c "$CMD"

      echo "Successfully copied packages to '${volume-nix-store}'."
    '';
}
