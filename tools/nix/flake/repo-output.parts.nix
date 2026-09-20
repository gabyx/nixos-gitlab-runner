{
  ...
}:
{
  # Defining a `perSystem` scoped module option `modos`.
  perSystem =
    {
      config,
      ...
    }:
    {
      # Expose the perSystem config.
      legacyPackages.repo = config.repo;
    };
}
