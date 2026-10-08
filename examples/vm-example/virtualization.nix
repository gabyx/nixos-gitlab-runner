{ lib, ... }: {
  # Gitlab-Runner service silently enables this.
  virtualisation.docker = {
    enable = lib.mkForce false;
  };
}
