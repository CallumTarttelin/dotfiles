{inputs}: final: prev: {
  ltrace = prev.ltrace.overrideAttrs (old: {
    # GCC 16 defaults to C++20, which warns about the demangle fixture's
    # volatile return type. DejaGNU treats compiler output as a failure.
    # Keep this legacy fixture on C++17 while retaining the full test suite.
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace testsuite/ltrace.minor/demangle.exp \
          --replace-fail '[list debug c++]' \
            '[list debug c++ additional_flags=-std=gnu++17]' \
          --replace-fail '[list debug shlib=$lib_sl c++]' \
            '[list debug shlib=$lib_sl c++ additional_flags=-std=gnu++17]'
      '';
  });

  jetbrains-toolbox =
    if final.stdenv.hostPlatform.isLinux
    then final.callPackage ../pkgs/jetbrains-toolbox {}
    else prev.jetbrains-toolbox;
}
