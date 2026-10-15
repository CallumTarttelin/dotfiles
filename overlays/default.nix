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

  pythonPackagesExtensions =
    prev.pythonPackagesExtensions
    ++ [
      (pyFinal: pyPrev: {
        debugpy = pyPrev.debugpy.overridePythonAttrs (old: {
          # On Darwin nixpkgs patches the lldb call to an absolute store path,
          # but this test still asserts the command starts with a bare `lldb `.
          # Hydra fails the same way, so there is no cached build to fall back on.
          disabledTests =
            (old.disabledTests or [])
            ++ final.lib.optionals final.stdenv.hostPlatform.isDarwin ["test_lldb_command"];
        });
      })
    ];

  jetbrains-toolbox =
    if final.stdenv.hostPlatform.isLinux
    then final.callPackage ../pkgs/jetbrains-toolbox {}
    else prev.jetbrains-toolbox;
}
