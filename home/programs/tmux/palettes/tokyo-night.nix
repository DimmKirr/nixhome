# Tokyo Night — palette shape matches Catppuccin's 26 slots.
# Source: https://github.com/folke/tokyonight.nvim (night variant)
rec {
  name = "tokyo-night";

  # Surfaces
  bg        = "#1a1b26";  # background
  fg        = "#c0caf5";  # foreground
  crust     = "#13131e";  # darkest
  mantle    = "#16161e";
  surface_0 = "#1f2335";
  surface_1 = "#24283b";  # bg_highlight
  surface_2 = "#292e42";
  overlay_0 = "#3b4261";  # terminal_black
  overlay_1 = "#414868";  # comment
  overlay_2 = "#545c7e";  # dark5
  subtext_0 = "#a9b1d6";
  subtext_1 = "#c0caf5";

  # Accents
  rosewater = "#f7768e";  # alias red (no distinct rosewater)
  flamingo  = "#f7768e";  # alias red
  pink      = "#ff007c";  # magenta2
  mauve     = "#bb9af7";  # purple
  red       = "#f7768e";
  maroon    = "#db4b4b";  # red1
  peach     = "#ff9e64";  # orange
  yellow    = "#e0af68";
  green     = "#9ece6a";
  teal      = "#73daca";  # teal
  sky       = "#7dcfff";  # sky
  sapphire  = "#2ac3de";  # cyan
  blue      = "#7aa2f7";
  lavender  = "#bb9af7";  # alias purple

  iconFgDefault = crust;

  flags = {
    active   = { icon = "";  color = blue;      };
    last     = { icon = "·"; color = subtext_0; };
    zoomed   = { icon = "Z"; color = peach;     };
    bell     = { icon = "!"; color = red;       };
    activity = { icon = "•"; color = yellow;    };
    silence  = { icon = "~"; color = overlay_0; };
  };
}
