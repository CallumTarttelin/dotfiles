{
  pkgs,
  config,
  ...
}: {
  programs.java = {
    enable = true;
    package = pkgs.jdk21;
  };

  programs.gradle = {
    enable = true;
    home = "${config.xdg.configHome}/gradle";
  };

  programs.go.enable = true;

  home.packages = with pkgs; [
    maven
    nodejs_24
    pnpm
    deno
    bun
    deno
    python3
    gleam
    erlang
    elixir
    ocaml
    zig

    python313Packages.ptpython
    poetry
  ];
}
