{ ... }: {
  perSystem =
    {
      self',
      pkgs,
      ...
    }:
    {
      repo.toolchains.githooks = [
        {
          git-hooks = {
            enable = true;
            package = pkgs.prek;
            configPath = "./tools/configs/prek/prek.toml";
            # WARNING: Only `pre-commit`, because Git LFS hooks might be ignored since `prek` does not support LFS.
            default_stages = [ "pre-commit" ];
          };

          packages = [ pkgs.prek ];
        }
      ];

      repo.toolchains.general = [
        {
          packages = [
            self'.packages.bootstrap
            self'.packages.treefmt
            self'.packages.generate-changelog
          ];
        }
      ];
    };
}
