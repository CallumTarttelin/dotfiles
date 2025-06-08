{
  pkgs,
  lib,
  ...
}: {
  services.mako = {
    enable = true;
    settings = {
      defaultTimeout = 3000;
      ignoreTimeout = true;
    };
  };
}
