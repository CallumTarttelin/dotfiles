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

    configDir = pkgs.runCommand "noctalia-config" {} ''
      mkdir -p $out/noctalia
      ${lib.optionalString hasState ''
        ${pkgs.jq}/bin/jq '.settings' ${stateFile} > $out/noctalia/settings.json
      ''}
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
              --set XDG_CONFIG_HOME "${configDir}"
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
  in {
    packages.myNoctalia = wrapped;
    packages.noctalia-save = saveScript;
  };

  flake.nixosModules.noctalia = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myNoctalia
      self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-save
      pkgs.fastfetch
      pkgs.openhue-cli
      pkgs.gpu-screen-recorder
    ];
  };
}
