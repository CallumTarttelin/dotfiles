{
  appimageTools,
  buildFHSEnv,
  coreutils,
  fetchzip,
  lib,
  runtimeShell,
  stdenvNoCC,
}: let
  pname = "jetbrains-toolbox";
  version = "3.6.1.85592";

  selectSystem = attrs:
    attrs.${stdenvNoCC.hostPlatform.system}
    or (throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}");

  archSuffix =
    if stdenvNoCC.hostPlatform.isAarch64
    then "-arm64"
    else "";

  src = fetchzip {
    url = "https://download.jetbrains.com/toolbox/jetbrains-toolbox-${version}${archSuffix}.tar.gz";
    hash = selectSystem {
      x86_64-linux = "sha256-GhrN3oGdNqE4cYJmSAeRATk2yS6AVF6z+/VIb7ttoJc=";
      aarch64-linux = "sha256-vI0niFirdAnYKF7+1+ACD31i86PgpPXUfKPkHttusRo=";
    };
  };
in
  buildFHSEnv {
    inherit pname version;

    passthru = {
      inherit src;
    };

    multiPkgs = pkgs:
      with pkgs;
        [
          icu
          libappindicator-gtk3
        ]
        ++ appimageTools.defaultFhsEnvArgs.multiPkgs pkgs;

    runScript = "${src}/bin/jetbrains-toolbox --update-failed";

    extraInstallCommands = ''
      install -Dm0644 ${src}/bin/jetbrains-toolbox.desktop -t $out/share/applications
      install -Dm0644 ${src}/bin/toolbox-tray-color.png $out/share/pixmaps/jetbrains-toolbox.png

      install -Dm0755 /dev/stdin $out/bin/jetbrains-toolbox-desktop <<EOF
      #!${runtimeShell}
      export SSH_AUTH_SOCK="\''${XDG_RUNTIME_DIR:-/run/user/\$(${coreutils}/bin/id -u)}/ssh-agent"
      exec "$out/bin/jetbrains-toolbox" "\$@"
      EOF

      substituteInPlace $out/share/applications/jetbrains-toolbox.desktop \
        --replace-fail "Exec=jetbrains-toolbox" "Exec=$out/bin/jetbrains-toolbox-desktop"
    '';

    meta = {
      description = "JetBrains Toolbox";
      homepage = "https://www.jetbrains.com/toolbox-app";
      license = lib.licenses.unfree;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      platforms = ["x86_64-linux" "aarch64-linux"];
      mainProgram = pname;
    };
  }
