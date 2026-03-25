{
  inputs,
  pkgs,
  self,
  ...
}: let
  llm-agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  t3code = self.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
in {
  home.packages = [
    llm-agents.claude-code
    llm-agents.codex
    llm-agents.codex-acp
    llm-agents.opencode
    t3code
  ];
}
