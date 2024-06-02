_: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    extraConfig = ''
      local wezterm = require 'wezterm'
      local config = wezterm.config_builder()
      local monokai = wezterm.color.get_builtin_schemes()['Monokai Pro (Gogh)']
      monokai.background = 'black'
      config.color_schemes = {
        ['My Monokai'] = monokai
      }
      config.color_scheme = 'My Monokai'
      config.scrollback_lines = 100000
      config.window_background_opacity = 0.6
      config.hide_tab_bar_if_only_one_tab = true
      config.window_padding = {
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
      }

      config.enable_wayland = false

      return config
    '';
  };
}
