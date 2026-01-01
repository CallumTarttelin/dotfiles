{
  description = "Neovim config flake using NixVim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixvim.url = "github:nix-community/nixvim";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = {
    nixvim,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem = {system, ...}: let
        pkgs = import inputs.nixpkgs {
          inherit system;
        };
        nixvim' = nixvim.legacyPackages.${system};
        nvim = nixvim'.makeNixvimWithModule {
          inherit pkgs;
          module = import ./config;
        };
      in {
        packages = {
          nvim = nvim;
          default = nvim;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.nil # Nix language server
            pkgs.alejandra # Nix formatter
            nvim
          ];
        };
      };
    };
}
