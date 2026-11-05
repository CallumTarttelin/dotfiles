{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  pins = builtins.fromJSON (builtins.readFile ./pins.json);
  package = name: installPhase:
    stdenv.mkDerivation {
      pname = name;
      inherit (pins.${name}) version;
      src = fetchurl {inherit (pins.${name}) url hash;};
      sourceRoot = ".";
      nativeBuildInputs = [autoPatchelfHook];
      buildInputs = [stdenv.cc.cc.lib];
      dontBuild = true;
      inherit installPhase;
      meta = {
        platforms = ["x86_64-linux"];
        license = lib.licenses.mit;
      };
    };
in {
  cliproxyapi = package "cliproxyapi" ''
    runHook preInstall
    install -Dm755 cli-proxy-api $out/bin/cliproxyapi
    runHook postInstall
  '';
  private-ai-proxy = (package "private-ai-proxy" ''
    runHook preInstall
    mkdir -p $out/bin
    cp private-ai-proxy-cli-*/private-ai-proxy* $out/bin/
    ln -s private-ai-proxy $out/bin/pap
    runHook postInstall
  '').overrideAttrs (old: {meta = old.meta // {license = lib.licenses.asl20;};});
}
