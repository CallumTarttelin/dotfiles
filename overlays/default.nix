{inputs}: final: prev: let
  firefox152Pkgs = import inputs.nixpkgs-firefox-152 {
    inherit (prev.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in {
  # Temporary workaround for the fontconfig 2.18 font-matching regression:
  # https://bugzilla.mozilla.org/show_bug.cgi?id=2051021
  # The warning turns the usual flake-update/rebuild into a removal reminder.
  firefox =
    prev.lib.warnIf
    (prev.lib.versionAtLeast prev.firefox.version "153")
    "Firefox ${prev.firefox.version} contains the fontconfig workaround; remove the temporary nixpkgs-firefox-152 pin."
    firefox152Pkgs.firefox;

  jetbrains-toolbox =
    if final.stdenv.hostPlatform.isLinux
    then final.callPackage ../pkgs/jetbrains-toolbox {}
    else prev.jetbrains-toolbox;
}
