{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-2511.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "hm";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };
    codex-desktop-linux = {
      url = "github:ilysenko/codex-desktop-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-desktop-debian = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell/legacy-v4";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }: let
    mkPkgs = system:
      import inputs.nixpkgs {
        inherit system;
        overlays = [
          (import ./overlays {inherit inputs;})
        ];
        config.allowUnfree = true;
        config.segger-jlink.acceptLicense = true;
        config.permittedInsecurePackages = ["segger-jlink-qt4-952"];
      };

    mkNeovim = system: let
      pkgs = mkPkgs system;
    in
      import ./pkgs/neovim {
        inherit pkgs;
        nixvim = inputs.nixvim;
      };

    mkRemoteZsh = system: let
      pkgs = mkPkgs system;
    in
      pkgs.callPackage ./pkgs/remote-zsh {
        inherit pkgs;
        neovim = mkNeovim system;
      };

    remoteZshApp = system: {
      type = "app";
      program = "${self.packages.${system}.remoteZsh}/bin/zsh";
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./hosts
        ./modules
        ./home/profiles
        # To import a flake module
        # 1. Add foo to inputs
        # 2. Add foo as a parameter to the outputs function
        # 3. Add here: foo.flakeModule
      ];
      systems = ["x86_64-linux"];
      perSystem = {system, ...}: let
        pkgs = mkPkgs system;
      in {
        _module.args.pkgs = pkgs;
        packages = import ./pkgs {
          inherit pkgs;
          nixvim = inputs.nixvim;
          flake = "/home/tarttelin/Documents/dotfiles";
        };
      };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.
        packages.aarch64-linux = let
          nvim = mkNeovim "aarch64-linux";
          remoteZsh = mkRemoteZsh "aarch64-linux";
        in {
          inherit nvim;
          myNeovim = nvim;
          inherit remoteZsh;
        };

        packages.aarch64-darwin = let
          nvim = mkNeovim "aarch64-darwin";
          remoteZsh = mkRemoteZsh "aarch64-darwin";
        in {
          inherit nvim;
          myNeovim = nvim;
          inherit remoteZsh;
        };

        apps = {
          x86_64-linux.remote-zsh = remoteZshApp "x86_64-linux";
          aarch64-linux.remote-zsh = remoteZshApp "aarch64-linux";
          aarch64-darwin.remote-zsh = remoteZshApp "aarch64-darwin";
        };

        deploy.nodes.nixie = {
          hostname = "nixie";
          magicRollback = false;
          profiles.system = {
            user = "root";
            path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nixie;
          };
        };
      };
    };
}
