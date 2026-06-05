{
  appimageTools,
  fetchurl,
  lib,
  makeDesktopItem,
}: let
  pname = "t3code";
  version = "0.0.25";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-aO1gFdYRs/9kvT8/1W4/v5e8os9E7rJl46BTK9SUglI=";
  };

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "T3 Code";
    comment = "Minimal desktop GUI for coding agents";
    exec = pname;
    terminal = false;
    categories = ["Development"];
  };
in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${desktopItem}/share/applications/${pname}.desktop \
        $out/share/applications/${pname}.desktop
    '';

    meta = with lib; {
      description = "Desktop app for coding agents";
      homepage = "https://github.com/pingdotgg/t3code";
      license = licenses.mit;
      mainProgram = pname;
      platforms = ["x86_64-linux"];
      sourceProvenance = with sourceTypes; [binaryNativeCode];
    };
  }
