{inputs}: final: prev: {
  pythonPackagesExtensions =
    prev.pythonPackagesExtensions
    ++ [
      (pyFinal: pyPrev: {
        mitmproxy = pyPrev.mitmproxy.overridePythonAttrs (old: let
          # Review this temporary backport whenever nixpkgs changes.
          reviewedNixpkgsRev = "f4a03c008967841f2a0b3cb7c436fc6fc31671f6";
          upstreamHasFix = builtins.any (patch: (patch.name or "") == "fix-test-emudhra.patch") (old.patches or []);
        in
          final.lib.warnIf
          (inputs.nixpkgs.rev != reviewedNixpkgsRev || upstreamHasFix)
          "Review the temporary mitmproxy eMudhra test backport in overlays/default.nix: nixpkgs changed or already includes the fix; remove the override once upstream provides it."
          {
            # CPython now rejects the compromised eMudhra intermediate keys in
            # these fixtures. Backport the upstream test fix used by nixpkgs.
            patches =
              (old.patches or [])
              ++ final.lib.optionals (!upstreamHasFix) [
                (final.fetchpatch {
                  name = "fix-test-emudhra.patch";
                  url = "https://github.com/mitmproxy/mitmproxy/commit/992052ee92d7ff4d240eafbe1afdf87c94b3f080.patch";
                  hash = "sha256-kxCt72m8G+yoAWe8xsXjt1U6B2Sh02u8MCFiqi18lng=";
                })
              ];
          });

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
