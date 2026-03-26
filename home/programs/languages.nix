# HM modules for env var setup (JAVA_HOME, GOPATH, GRADLE_HOME).
# Packages are in modules/bundles/ (go-tools, jvm-tools, web-tools, etc.)
{
  config,
  pkgs,
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
}
