{
  pkgs,
  lib,
  ...
}: {
  programs.wofi = {
    enable = true;
    settings = {
      xoffset = "0px";
      yoffset = "0px";
      hide_scroll = "true";
      show = "drun";
      width = "15%";
      lines = "15";
      line_wrap = "word";
      term = "foot";
      allow_markup = true;
      always_parse_args = true;
      show_all = true;
      print_command = true;
      layer = "overlay";
      allow = "images=true";
      insensitive = true;
      prompt = "";
      image_size = "30";
      display_generic = true;
      key_expand = "Tab";
    };

    style = ''
      #entry {
      border-radius: 5px;
      padding: 7px;
      margin: 0px 5px 9px 5px;
      }

      @keyframes fadeIn {
        from {opacity: 0;}
        to {opacity: 1;}
      }

      #entry:selected {
      background-color: #5e81ac;
      font-weight: bold;
      }

      #text:selected {
      color: #d8dee9;
      }

      #window {
      background-color: #434c5e;
      background-color: transparent;
      border-radius: 15px;
      font-family: Jetbrains Mono;
      animation: fadeIn;
      animation-duration: 0.3s;
      }

      #input {
      border: none;
      background-color: #4c566a;
      padding: 9px;
      margin: 15px;
      margin-bottom: 0px;
      font-size: 16px;
      border-radius: 5px;
      }

      #inner-box {
      color: #d8dee9;
      padding-top: 5px;
      margin: 10px;
      border-radius: 10px;
      }

      #outer-box {
      margin: 15px;
      border-radius: 15px;
      background-color: rgba(53,59,73,1.0);
      box-shadow: 0px 0px 5px 0  #0F0F0F;
      }

      #scroll {
      margin-bottom: 10px;
      }

      #text {
      font-size: 14px;
      padding: 5px;
      color: #d8dee9;
      background-color: transparent;
      }

      #img {
        background-color: transparent;
        padding: 5px;
      }

    '';
  };
}
