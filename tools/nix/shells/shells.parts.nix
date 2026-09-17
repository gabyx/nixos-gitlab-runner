{
  self,
  ...
}:
{
  perSystem =
    {
      self',
      config,
      ...
    }:
    let
      args = config.allModuleArgs; # See https://flake.parts/module-arguments#obtaining-all-module-arguments
      inherit (config) toolchains;
    in
    {
      devShells.default = self.lib.shell.mkShell {
        inherit (args) system;
        modules = toolchains.general ++ toolchains.githooks;
      };

      devShells.default-nogh = self.lib.shell.mkShell {
        inherit (args) system;
        modules = toolchains.general;
      };

      # The CI shell is the same as the default.
      devShells.ci = self'.devShells.default-nogh;
    };
}
