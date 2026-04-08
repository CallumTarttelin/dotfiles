{self, ...}: {
  perSystem = {
    pkgs,
    self',
    lib,
    ...
  }: let
    atuinConf = (pkgs.formats.toml {}).generate "atuin-config.toml" {
      dialect = "uk";
      sync_address = "http://nixie.oryx-harmonic.ts.net:8888";
      sync_frequency = "0";
      enter_accept = true;
      style = "full";
      inline_height = 0;
    };

    skimDefaultCommand = "fd --type f";
    skimChangeDirCommand = "fd --type d";

    zshConf = pkgs.writeText "zshrc" ''
      # Restore wrapped PATH (NixOS set-environment resets it for login shells)
      export PATH="${lib.makeBinPath runtimeInputs}:$PATH"

      # history
      HISTFILE="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh_history"
      HISTSIZE=10000
      SAVEHIST=10000
      setopt EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST SHARE_HISTORY

      # autocd
      setopt AUTO_CD

      # dir hashes
      hash -d dl="$HOME/Downloads"
      hash -d docs="$HOME/Documents"
      hash -d dots="$HOME/Documents/dotfiles"

      # autosuggestions
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh

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
      zstyle ':completion:*' list-colors \'
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
        if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }

      # ssh-agent (systemd user service provides the socket)
      if [ -z "$SSH_AUTH_SOCK" -o -z "$SSH_CONNECTION" ]; then
        export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent"
      fi

      # shell integrations
      eval "$(zoxide init zsh)"
      eval "$(${lib.getExe self'.packages.myStarship} init zsh)"
      eval "$(atuin init zsh)"
      eval "$(direnv hook zsh)"
      source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc

      # skim
      source ${pkgs.skim}/share/skim/key-bindings.zsh
      source ${pkgs.skim}/share/skim/completion.zsh
      export SKIM_DEFAULT_COMMAND="${skimDefaultCommand}"
      export SKIM_CTRL_T_COMMAND="${skimDefaultCommand}"
      export SKIM_ALT_C_COMMAND="${skimChangeDirCommand}"

      # aliases
      alias grep="grep --color"
      alias ip="ip --color"
      alias sizeof="du -sh"
      alias icat="wezterm imgcat"
      alias us="systemctl --user"
      alias rs="sudo systemctl"
      alias vi="nvim"
      alias vim="nvim"
      alias ex="hyprctl dispatch exec"
      function exd() {
        local env_args=()
        if [[ "$1" == "-E" ]]; then
          shift
          while IFS='=' read -r k v; do
            [[ "$k" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || continue
            env_args+=("--setenv=$k=$v")
          done < <(env)
        fi
        local suffix="$$-$RANDOM"
        systemd-run --user --collect "''${env_args[@]}" --unit="app-''${1##*/}-$suffix" -- "$@"
      }
      alias cat="bat"
      alias ls="eza --icons=auto --git"
      alias ll="eza --icons=auto --git -lga"
      alias la="eza --icons=auto --git -a"
      alias lt="eza --icons=auto --git -T -L 1"
      alias ltt="eza --icons=auto --git -T -L 2"
      alias lttt="eza --icons=auto --git -T -L 3"
      alias tree="eza --icons=auto --git -T"
    '';

    runtimeInputs = [
      self'.packages.myStarship
      pkgs.bat
      pkgs.btop
      pkgs.zoxide
      pkgs.eza
      pkgs.skim
      pkgs.fd
      pkgs.ripgrep
      pkgs.dust
      pkgs.duf
      pkgs.jq
      pkgs.file
      pkgs.htop
      pkgs.killall
      pkgs.lsof
      pkgs.atuin
      pkgs.direnv
      pkgs.nix-direnv
      pkgs.yazi
      pkgs.tmux
      pkgs.zip
      pkgs.unzip
      pkgs.glow
      pkgs.zellij
      pkgs.jujutsu
      pkgs.lazyjj
      pkgs.jjui
      pkgs.lazygit
      pkgs.git-agecrypt
      pkgs.git-credential-keepassxc
    ];
  in {
    packages.myZsh = let
      # Create a ZDOTDIR with our zshrc at build time (immutable, in nix store)
      zdotdir = pkgs.runCommand "zsh-dotdir" {} ''
        mkdir -p $out
        cp ${zshConf} $out/.zshrc
      '';
      # Create atuin config dir at build time
      atuinDir = pkgs.runCommand "atuin-config" {} ''
        mkdir -p $out
        cp ${atuinConf} $out/config.toml
      '';
    in
      pkgs.symlinkJoin {
        name = "myZsh";
        paths = [pkgs.zsh];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/zsh \
            --set EDITOR "${lib.getExe pkgs.neovim}" \
            --set MANPAGER "sh -c 'col -bx | bat -l man -p'" \
            --set MANROFFOPT "-c" \
            --set NIX_AUTO_RUN "1" \
            --set ATUIN_CONFIG_DIR "${atuinDir}" \
            --set ZDOTDIR "${zdotdir}" \
            --prefix PATH : ${lib.makeBinPath runtimeInputs}
        '';
        passthru = {shellPath = "/bin/zsh";};
      };
  };

  flake.nixosModules.myZsh = {pkgs, ...}: {
    home-manager.users.tarttelin.home.packages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.myZsh
    ];
  };
}
