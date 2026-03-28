# Noctalia desktop shell.
#
# Per-host state: each host has its own _noctalia-state-<hostname>.json
# To update config: run `noctalia-save` then `nh os switch`
{inputs, self, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    noctaliaPkg = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    flakeDir = "/home/tarttelin/Documents/dotfiles";

    mkNoctalia = hostname: let
      stateFile = ./_noctalia-state-${hostname}.json;
      hasState = builtins.pathExists stateFile;
      settingsFile = pkgs.runCommand "noctalia-settings-${hostname}" {} ''
        ${pkgs.jq}/bin/jq '.settings' ${stateFile} > $out
      '';
    in
      if hasState
      then
        pkgs.symlinkJoin {
          name = "myNoctalia-${hostname}";
          paths = [noctaliaPkg];
          nativeBuildInputs = [pkgs.makeWrapper];
          postBuild = ''
            wrapProgram $out/bin/noctalia-shell \
              --set NOCTALIA_SETTINGS_FILE "${settingsFile}"
          '';
          meta.mainProgram = "noctalia-shell";
        }
      else noctaliaPkg;

    mkSaveScript = hostname:
      pkgs.writeShellScriptBin "noctalia-save" ''
        dest="${flakeDir}/modules/wrapped/_noctalia-state-${hostname}.json"
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
    packages.myNoctalia-nixshark = mkNoctalia "nixshark";
    packages.myNoctalia-nixwork = mkNoctalia "nixwork";
    packages.noctalia-save-nixshark = mkSaveScript "nixshark";
    packages.noctalia-save-nixwork = mkSaveScript "nixwork";
    packages.noctalia-restart = restartScript;
  };

  flake.nixosModules.noctalia = {
    config,
    pkgs,
    ...
  }: let
    hostname = config.networking.hostName;
    system = pkgs.stdenv.hostPlatform.system;
  in {
    home-manager.users.tarttelin = {
      home.packages = [
        self.packages.${system}."myNoctalia-${hostname}"
        self.packages.${system}."noctalia-save-${hostname}"
        self.packages.${system}.noctalia-restart
        pkgs.fastfetch
        pkgs.openhue-cli
        pkgs.gpu-screen-recorder
      ];

      # Install iwd-connections plugin to noctalia config dir
      home.file.".config/noctalia/plugins/iwd-connections".source = ../plugins/iwd-connections;
    };
  };
}
