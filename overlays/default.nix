final: prev: {
  jetbrains-toolbox =
    if final.stdenv.hostPlatform.isLinux
    then final.callPackage ../pkgs/jetbrains-toolbox {}
    else prev.jetbrains-toolbox;
}
