{pkgs, config, ...}: {

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
    nodejs_20
    deno
    bun
    python3
    gleam
    erlang
    elixir
    ocaml
    zig
  ];

}
