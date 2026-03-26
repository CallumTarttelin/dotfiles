{inputs, self, ...}: {
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

  flake.nixosModules.llms = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.llms
    ];
  };
}
