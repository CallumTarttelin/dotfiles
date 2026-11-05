{
  pkgs,
  flake,
  nixvim,
}: let
  updateT3code = pkgs.callPackage ./update-t3code {inherit flake;};
  updateJetbrainsToolbox = pkgs.callPackage ./update-jetbrains-toolbox {inherit flake;};
  updateInference = pkgs.callPackage ./update-inference {inherit flake;};
  inferenceTools = pkgs.callPackage ./inference-tools {};
  nvim = import ./neovim {inherit pkgs nixvim;};
  remoteZsh = pkgs.callPackage ./remote-zsh {
    inherit pkgs;
    neovim = nvim;
  };
in {
  inherit nvim;
  myNeovim = nvim;
  inherit remoteZsh;

  jetbrains-toolbox = pkgs.jetbrains-toolbox;
  gcloud-remote-login = pkgs.callPackage ./gcloud-remote-login {};
  localproxy = pkgs.callPackage ./localproxy {};
  inherit (inferenceTools) cliproxyapi private-ai-proxy;
  inference-gateway = pkgs.callPackage ./inference-gateway {};
  update-inference = updateInference;
  t3code = pkgs.callPackage ./t3code {};
  update-t3code = updateT3code;
  update-jetbrains-toolbox = updateJetbrainsToolbox;
  pre-update = pkgs.callPackage ./pre-update {
    inherit updateJetbrainsToolbox updateT3code updateInference;
  };
}
