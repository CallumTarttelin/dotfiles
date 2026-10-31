{
  inputs,
  lib,
  ...
}: let
  # Add named skill directories here; pin remote sources as flake inputs.
  skills = {
    igloo = "${inputs.igloo}/skills/igloo";
  };
in {
  home.file = lib.mapAttrs' (name: source:
    lib.nameValuePair ".codex/skills/${name}" {
      inherit source;
    })
  skills;
}
