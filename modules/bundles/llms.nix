{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    llm-agents = inputs.llm-agents.packages.${system};
  in {
    packages.llms = pkgs.buildEnv {
      name = "llm-tools";
      paths = [
        llm-agents.claude-code
        llm-agents.codex
        llm-agents.codex-acp
        llm-agents.opencode
        self.packages.${system}.t3code
      ];
    };
  };

  flake.nixosModules.llms = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.bundles.llms.enable = lib.mkEnableOption "LLM tools (claude-code, codex, opencode)";
    config = lib.mkIf config.bundles.llms.enable {
      home-manager.users.tarttelin.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.llms
      ];
    };
  };
}
