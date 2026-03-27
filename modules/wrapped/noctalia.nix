# Noctalia desktop shell.
#
# To update config: run `noctalia-save` then `nh os switch`
# This dumps the live noctalia state and rebuilds with it baked in.
{inputs, self, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    noctaliaPkg = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    stateFile = ./_noctalia-state.json;
    hasState = builtins.pathExists stateFile;

    settingsFile = pkgs.runCommand "noctalia-settings" {} ''
      ${pkgs.jq}/bin/jq '.settings' ${stateFile} > $out
    '';

    wrapped =
      if hasState
      then
        pkgs.symlinkJoin {
          name = "myNoctalia";
          paths = [noctaliaPkg];
          nativeBuildInputs = [pkgs.makeWrapper];
          postBuild = ''
            wrapProgram $out/bin/noctalia-shell \
              --set NOCTALIA_SETTINGS_FILE "${settingsFile}"
          '';
          meta.mainProgram = "noctalia-shell";
        }
      else noctaliaPkg;

    flakeDir = "/home/tarttelin/Documents/dotfiles";
    saveScript = pkgs.writeShellScriptBin "noctalia-save" ''
      dest="${flakeDir}/modules/wrapped/_noctalia-state.json"
      ${lib.getExe noctaliaPkg} ipc call state all > "$dest"
      echo "Saved noctalia state to $dest"
      echo "Run 'nh os switch' to bake it in"
    '';

    restartScript = pkgs.writeShellScriptBin "noctalia-restart" ''
      echo "Clearing QML cache..."
      rm -rf "''${XDG_CACHE_HOME:-$HOME/.cache}/noctalia-qs/qmlcache"
      echo "Restarting noctalia-shell..."
      systemctl --user restart noctalia-shell.service
    '';
  in {
    packages.myNoctalia = wrapped;
    packages.noctalia-save = saveScript;
    packages.noctalia-restart = restartScript;
  };

  flake.nixosModules.noctalia = {pkgs, ...}: {
    home-manager.users.tarttelin = {
      home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myNoctalia
        self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-save
        self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-restart
        pkgs.fastfetch
        pkgs.openhue-cli
        pkgs.gpu-screen-recorder
      ];

      # Install iwd-connections plugin to noctalia config dir
      home.file.".config/noctalia/plugins/iwd-connections".source = ../plugins/iwd-connections;
    };
  };
}
