{inputs}: final: prev: let
  # fontconfig 2.18.1 can select Noto Color Emoji for spaces and digits.
  # Drop this override automatically once nixpkgs contains the upstream fix.
  needsFontconfigFix =
    prev.stdenv.hostPlatform.isLinux
    && prev.lib.versionOlder prev.fontconfig.version "2.18.2";

  fontconfigFixed = prev.fontconfig.overrideAttrs (_: {
    version = "2.18.2";
    src = prev.fetchurl {
      url = "https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.18.2/fontconfig-2.18.2.tar.xz";
      hash = "sha256-z45ldu8EhMFQeb2vd82cUcRk31NlgUraTT7nMx6jHrU=";
    };
    patches = [];
  });

  patchFirefox = firefox:
    firefox
    // (prev.replaceDependency {
      drv = firefox;
      oldDependency = prev.fontconfig.lib;
      newDependency = fontconfigFixed.lib;
      verbose = false;
    })
    // {
      inherit (firefox) meta passthru version;
      override = args: patchFirefox (firefox.override args);
    };

  firefoxWithFontconfigFix = patchFirefox prev.firefox;
in {
  firefox =
    if needsFontconfigFix
    then firefoxWithFontconfigFix
    else
      prev.lib.warnIf
      prev.stdenv.hostPlatform.isLinux
      "nixpkgs now contains fontconfig ${prev.fontconfig.version}; remove the temporary Firefox fontconfig 2.18.2 overlay."
      prev.firefox;

  jetbrains-toolbox =
    if final.stdenv.hostPlatform.isLinux
    then final.callPackage ../pkgs/jetbrains-toolbox {}
    else prev.jetbrains-toolbox;
}
