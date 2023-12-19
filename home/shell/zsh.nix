{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    autocd = true;
    dirHashes = {
      dl = "$HOME/Downloads";
      docs = "$HOME/Documents";
      dots = "$HOME/Documents/dotfiles";
    };
    dotDir = ".config/zsh";
    history = {
      expireDuplicatesFirst = true;
      path = "${config.xdg.dataHome}/zsh_history";
    };

    initExtra = ''
      # search history based on what's typed in the prompt
      autoload -U history-search-end
      zle -N history-beginning-search-backward-end history-search-end
      zle -N history-beginning-search-forward-end history-search-end
      bindkey "^[OA" history-beginning-search-backward-end
      bindkey "^[OB" history-beginning-search-forward-end

      # C-right / C-left for word skips
      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word

      # C-Backspace / C-Delete for word deletions
      bindkey "^[[3;5~" forward-kill-word
      bindkey "^H" backward-kill-word

      # Home/End
      bindkey "^[[OH" beginning-of-line
      bindkey "^[[OF" end-of-line

      # open commands in $EDITOR with C-e
      autoload -z edit-command-line
      zle -N edit-command-line
      bindkey "^e" edit-command-line

      # case insensitive tab completion
      zstyle ':completion:*' completer _complete _ignored _approximate
      zstyle ':completion:*' list-colors '\'
      zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' menu select
      zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
      zstyle ':completion:*' verbose true
      _comp_options+=(globdots)

      ${lib.optionalString config.services.gpg-agent.enable ''
        gnupg_path=$(ls $XDG_RUNTIME_DIR/gnupg)
        export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gnupg/$gnupg_path/S.gpg-agent.ssh"
      ''}

      ${lib.optionalString config.programs.kitty.enable ''
        if test -n "$KITTY_INSTALLATION_DIR"; then
          export KITTY_SHELL_INTEGRATION="enabled"
          autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
          kitty-integration
          unfunction kitty-integration
        fi
      ''}

      ${lib.optionalString config.services.atuin.enable ''
        eval "$(atuin gen-completion --shell zsh)"
        eval "$(atuin init zsh --disable-up-arrow)"
      ''}
    '';

    shellAliases =
      {
        grep = "grep --color";
        ip = "ip --color";
        sizeof = "du -sh";

        l = "eza -l";
        ls = "eza";
        la = "eza -a";
        lal = "eza -a -l";
        ll = "eza -l";
        lt = "eza -T -L 2 -I node_modules";
        lat = "eza -a -T -L 2 -I node_modules";
        ltt = "eza -T -L 3 -I node_modules";
        latt = "eza -a -T -L 3 -I node_modules";
        lttt = "eza -T -L 4 -I node_modules";
        lattt = "eza -a -T -L 4 -I node_modules";

        us = "systemctl --user";
        rs = "sudo systemctl";
      }
      // lib.optionalAttrs (config.programs.bat.enable == true) {cat = "bat";};
    shellGlobalAliases = {eza = "eza --icons --git";};
  };
}
