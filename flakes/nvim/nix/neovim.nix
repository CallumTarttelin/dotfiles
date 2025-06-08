{
  symlinkJoin,
  neovim-unwrapped,
  makeWrapper,
  runCommandLocal,
  vimPlugins,
  lib,
  pkgs,
}: let
  packageName = "mynvim";

  lsps = [
    pkgs.lua-language-server
    pkgs.clang
    pkgs.pyright
    pkgs.rust-analyzer
    pkgs.gopls
    pkgs.bash-language-server
    pkgs.nil
    pkgs.stylua
    pkgs.java-language-server
    pkgs.kotlin-language-server
    pkgs.git
    pkgs.curl
  ];

  startPlugins = [
    vimPlugins.lz-n
  ];

  optPlugins = [
    vimPlugins.plenary-nvim
    vimPlugins.telescope-nvim
    vimPlugins.telescope-fzf-native-nvim
    vimPlugins.telescope-ui-select-nvim
    vimPlugins.nvim-web-devicons
    vimPlugins.nvim-treesitter.withAllGrammars
    vimPlugins.vim-sleuth
    vimPlugins.gitsigns-nvim
    vimPlugins.which-key-nvim
    vimPlugins.fidget-nvim
    vimPlugins.conform-nvim
    vimPlugins.nvim-lspconfig
    vimPlugins.blink-cmp
    vimPlugins.friendly-snippets
    vimPlugins.tokyonight-nvim
    vimPlugins.todo-comments-nvim
    vimPlugins.mini-nvim
    vimPlugins.luasnip
    vimPlugins.cmp_luasnip
    vimPlugins.nvim-cmp
    vimPlugins.cmp-nvim-lsp
    vimPlugins.cmp-path
    vimPlugins.cmp-nvim-lsp-signature-help
  ];

  foldPlugins = builtins.foldl' (
    acc: next:
      acc
      ++ [
        next
      ]
      ++ (foldPlugins (next.dependencies or []))
  ) [];

  startPluginsWithDeps = lib.unique (foldPlugins startPlugins);
  optPluginsWithDeps = lib.unique (foldPlugins optPlugins);

  packpath = runCommandLocal "packpath" {} ''
    mkdir -p $out/pack/${packageName}/{start,opt}
    ${
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}")
      startPluginsWithDeps
    }
    ${
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/opt/${lib.getName plugin}")
      optPluginsWithDeps
    }
  '';
in
  symlinkJoin {
    name = "neovim-custom";
    paths = [
      neovim-unwrapped
    ];
    nativeBuildInputs = [makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/nvim \
        --add-flags '-u' \
        --add-flags '${../nvim/init.lua}' \
        --add-flags '--cmd' \
        --add-flags "'set packpath^=${packpath} | set runtimepath^=${packpath}'" \
        --prefix PATH : ${lib.makeBinPath lsps} \
        --set-default NVIM_APPNAME nvim-custom
      cp $out/bin/nvim $out/bin/neovim-custom
    '';
    passthru = {
      inherit packpath;
    };
  }
