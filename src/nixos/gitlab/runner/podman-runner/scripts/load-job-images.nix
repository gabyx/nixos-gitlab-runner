# Script to load all job images.
{
  lib,
  writeShellApplication,
  podman,
  images,
}:
writeShellApplication {
  name = "gitlab-runner-load-job-images";

  runtimeInputs = [
    podman
  ];

  text =
    # Bash
    ''
      set -e
      set -u

      imgs=(
        ${lib.concatMapStringsSep "\n" (img: "\"${img}\"") (lib.attrValues images)}
      )

      for img in "''${imgs[@]}"; do
        echo "Load image '$img'."
        podman load -i "$img"
      done

      echo "Successfully loaded all images."
    '';
}
