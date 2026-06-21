{
  lib,
  neovim,
  pkgs,
  extraZshConfig ? "",
  extraRuntimeInputs ? [],
}: let
  atuinConf = (pkgs.formats.toml {}).generate "remote-atuin-config.toml" {
    dialect = "uk";
    auto_sync = false;
    update_check = false;
    sync_address = "http://127.0.0.1:9";
    sync_frequency = "0";
    enter_accept = true;
    style = "full";
    inline_height = 0;

    sync.records = false;
    daemon = {
      enabled = false;
      autostart = false;
    };
  };

  starshipConf = (pkgs.formats.toml {}).generate "remote-starship.toml" {
    character = {
      success_symbol = "[λ](bold green)";
      error_symbol = "[λ](bold red)";
    };
    aws.disabled = true;
    gcloud.disabled = true;
    cmd_duration = {
      min_time = 500;
      format = "took [$duration](bold yellow)";
    };
  };

  skimDefaultCommand = "fd --type f";
  skimChangeDirCommand = "fd --type d";

  builtInRuntimeInputs = with pkgs; [
    neovim
    starship
    bat
    zoxide
    eza
    skim
    fd
    ripgrep
    jq
    file
    atuin
    direnv
    yazi
    tmux
    zip
    unzip
  ];

  runtimeInputs = builtInRuntimeInputs ++ extraRuntimeInputs;

  zshConf = pkgs.writeText "remote-zshrc" ''
    # Restore wrapped PATH for login shells that reset it.
    export PATH="${lib.makeBinPath runtimeInputs}:$PATH"

    # history
    HISTFILE="''${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
    HISTSIZE=10000
    SAVEHIST=10000
    mkdir -p -- "''${HISTFILE:h}"
    setopt EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST SHARE_HISTORY

    # autocd
    setopt AUTO_CD

    # autosuggestions
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh

    # syntax highlighting
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

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
    autoload -Uz compinit
    compinit
    zstyle ':completion:*' completer _complete _ignored _approximate
    zstyle ':completion:*' list-colors ""
    zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
    zstyle ':completion:*' menu select
    zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
    zstyle ':completion:*' verbose true
    _comp_options+=(globdots)

    # yazi cwd integration
    function y() {
      local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
      yazi "$@" --cwd-file="$tmp"
      if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
      fi
      rm -f -- "$tmp"
    }

    # shell integrations
    eval "$(zoxide init zsh)"
    eval "$(starship init zsh)"
    eval "$(atuin init zsh)"
    eval "$(direnv hook zsh)"

    # skim
    source ${pkgs.skim}/share/skim/key-bindings.zsh
    source ${pkgs.skim}/share/skim/completion.zsh
    export SKIM_DEFAULT_COMMAND="${skimDefaultCommand}"
    export SKIM_CTRL_T_COMMAND="${skimDefaultCommand}"
    export SKIM_ALT_C_COMMAND="${skimChangeDirCommand}"

    # aliases
    alias grep="grep --color=auto"
    alias sizeof="du -sh"
    alias vi="nvim"
    alias vim="nvim"
    alias cat="bat"
    alias ls="eza --icons=auto --git"
    alias ll="eza --icons=auto --git -lga"
    alias la="eza --icons=auto --git -a"
    alias lt="eza --icons=auto --git -T -L 1"
    alias ltt="eza --icons=auto --git -T -L 2"
    alias lttt="eza --icons=auto --git -T -L 3"
    alias tree="eza --icons=auto --git -T"

    ${extraZshConfig}

    # Source machine-local remote-zsh config if present.
    remote_zsh_local_rc="''${REMOTE_ZSH_LOCAL_RC:-''${XDG_CONFIG_HOME:-$HOME/.config}/remote-zsh/local.zsh}"
    if [[ -r "$remote_zsh_local_rc" ]]; then
      source "$remote_zsh_local_rc"
    fi
    unset remote_zsh_local_rc
  '';
in
  pkgs.symlinkJoin {
    name = "remoteZsh";
    paths = [pkgs.zsh];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      mkdir -p $out/share/remote-zsh/atuin $out/share/remote-zsh/zdotdir $out/share/remote-zsh/starship
      cp ${atuinConf} $out/share/remote-zsh/atuin/config.toml
      cp ${zshConf} $out/share/remote-zsh/zdotdir/.zshrc
      cp ${starshipConf} $out/share/remote-zsh/starship/starship.toml

      wrapProgram $out/bin/zsh \
        --set EDITOR "vi" \
        --set ATUIN_CONFIG_DIR "$out/share/remote-zsh/atuin" \
        --set STARSHIP_CONFIG "$out/share/remote-zsh/starship/starship.toml" \
        --set ZDOTDIR "$out/share/remote-zsh/zdotdir" \
        --prefix PATH : ${lib.makeBinPath runtimeInputs}
    '';
    passthru = {
      shellPath = "/bin/zsh";
      inherit atuinConf starshipConf zshConf;
    };
    meta.mainProgram = "zsh";
  }
