{pkgs, inputs, ...}:
let
  oldUnfree = import inputs.oldpkgs {
    config.allowUnfree = true;
    system = "x86_64-linux";
  };
in
{
  home.packages = with pkgs; [
    oldUnfree.citrix_workspace_23_09_0
    zoom-us
  ];
}
