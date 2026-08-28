{
  appimageTools,
  fetchurl,
  lib,
  makeDesktopItem,
}: let
  pname = "t3code";
  version = "0.0.35";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-l1ZNib2y0bRfL7GRYYPznUo4Q0nex4jV+2+yxkOuB5Q=";
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
