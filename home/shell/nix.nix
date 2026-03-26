{...}: {
  # nix-index-database provides comma + command-not-found
  programs.nix-index-database.comma.enable = true;

  # direnv is now in the wrapped zsh (runtimeInput + eval in zshrc)
}
