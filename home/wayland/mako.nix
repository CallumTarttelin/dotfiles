{
  pkgs,
  lib,
  ...
}: {
  services.mako = {
    enable = true;
    defaultTimeout = 3000;
    ignoreTimeout = true;
  };
}
