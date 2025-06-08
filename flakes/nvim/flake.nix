{
  description = "Neovim config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    gen-luarc = {
      url = "github:mrcjkb/nix-gen-luarc-json";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        inputs.gen-luarc.overlays.default
      ];
    };
    nvimPkg = import ./nix/default.nix {inherit pkgs;};
    # helloPkg = nixpkgs.legacyPackages.x86_64-linux.hello;
  in {
    inherit pkgs;
    packages.${system} = {
      nvim = nvimPkg;
      default = nvimPkg;
    };
    devshells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.lua-language-server
        pkgs.nil
        pkgs.stylua
        pkgs.luajitPackages.luacheck
        pkgs.nvim-dev
        nvimPkg
      ];
      shellHook = ''
        # symlink the .luarc.json generated in the overlay
        ln -fs ${pkgs.nvim-luarc-json} .luarc.json
        # allow quick iteration of lua configs
        ln -Tfns $PWD/nvim ~/.config/nvim-dev
      '';
    };
  };
}
