# Noctalia desktop shell.
#
# Per-host state: each host has its own _noctalia-state-<hostname>.json
# To update config: run `noctalia-save` then `nh os switch`
{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    noctaliaPkg = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
    flakeDir = "/home/tarttelin/Documents/dotfiles";

    mkNoctalia = hostname: let
      executableName = builtins.baseNameOf (lib.getExe noctaliaPkg);
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
            wrapProgram $out/bin/${executableName} \
              --set NOCTALIA_SETTINGS_FILE "${settingsFile}"
          '';
          meta.mainProgram = executableName;
        }
      else noctaliaPkg;

    mkSaveScript = hostname:
      pkgs.writeShellScriptBin "noctalia-save" ''
        dest="${flakeDir}/modules/wrapped/_noctalia-state-${hostname}.json"
        ${lib.getExe noctaliaPkg} ipc call state all > "$dest"
        cp ~/.config/noctalia/plugins.json "${flakeDir}/modules/wrapped/_noctalia-plugins-${hostname}.json"
        echo "Saved noctalia state and plugins to $dest"
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
    lib,
    pkgs,
    ...
  }: let
    cfg = config.noctalia;
    hostname = config.networking.hostName;
    inherit (pkgs.stdenv.hostPlatform) system;
  in {
    options.noctalia.enable = lib.mkEnableOption "Noctalia desktop shell plugins and tooling";

    config = lib.mkIf cfg.enable {
      home-manager.users.tarttelin = {
        home.packages = [
          self.packages.${system}."noctalia-save-${hostname}"
          self.packages.${system}.noctalia-restart
          pkgs.fastfetch
          pkgs.openhue-cli
          pkgs.gpu-screen-recorder
        ];

        # Install iwd-connections plugin to noctalia config dir
        home.file.".config/noctalia/plugins/iwd-connections".source = ../plugins/iwd-connections;

        # Seed plugin registry on fresh installs (mutable — noctalia needs to write to it)
        home.activation.noctalia-plugins = {
          after = ["writeBoundary"];
          before = [];
          data = ''
            pluginsFile="$HOME/.config/noctalia/plugins.json"
            if [ ! -f "$pluginsFile" ]; then
              mkdir -p "$(dirname "$pluginsFile")"
              cp ${./_noctalia-plugins-${hostname}.json} "$pluginsFile"
            fi
          '';
        };
      };
    };
  };
}
