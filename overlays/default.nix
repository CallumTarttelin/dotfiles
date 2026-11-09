{inputs}: final: prev: {
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
