{
  flake.nixosModules.remote-oidc-token = {
    config,
    lib,
    pkgs,
    self,
    ...
  }: let
    cfg = config.features.remote-oidc-token;
    package = self.packages.${pkgs.stdenv.hostPlatform.system}.remote-oidc-token;
    # Hosts, profile path, login issuer and storage locations live in the secret.
    wrapped = pkgs.symlinkJoin {
      name = "remote-oidc-token-${package.version}";
      paths = [package];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram "$out/bin/remote-oidc-token" \
          --set-default REMOTE_OIDC_TOKEN_CONFIG ${lib.escapeShellArg config.age.secrets.remote-oidc-token.path} \
          --prefix PATH : ${lib.makeBinPath [pkgs.openssh]}
      '';
      inherit (package) meta;
    };
  in {
    options.features.remote-oidc-token = {
      enable = lib.mkEnableOption "remote-oidc-token, which copies an OIDC web app's access token from the work browser to a dev box";

      configFile = lib.mkOption {
        type = lib.types.path;
        default = ../../secrets/remote-oidc-token.age;
        description = "Age-encrypted JSON config for remote-oidc-token.";
      };
    };

    config = lib.mkIf cfg.enable {
      age.secrets.remote-oidc-token = {
        file = cfg.configFile;
        owner = "tarttelin";
        group = "users";
        mode = "0400";
      };

      home-manager.users.tarttelin.home.packages = [wrapped];
    };
  };
}
