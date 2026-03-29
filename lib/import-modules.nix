lib: dir: {
  imports =
    builtins.filter
    (f: lib.hasSuffix ".nix" f && !(lib.hasInfix "/_" f))
    (lib.filesystem.listFilesRecursive dir);
}
