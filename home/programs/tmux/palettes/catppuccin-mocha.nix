# Catppuccin Mocha — canonical palette shape (26 named colors).
# Source: https://github.com/catppuccin/tmux/blob/main/themes/catppuccin_mocha_tmux.conf
#
# All other palettes MUST expose the same attribute names. Palettes with fewer
# distinct colors (Dracula, Nord) alias slots upward — duplicates are fine.
{
  name = "catppuccin-mocha";

  # Surfaces
  bg        = "#1e1e2e";  # base
  fg        = "#cdd6f4";  # text
  crust     = "#11111b";  # darkest
  mantle    = "#181825";
  surface_0 = "#313244";
  surface_1 = "#45475a";
  surface_2 = "#585b70";
  overlay_0 = "#6c7086";
  overlay_1 = "#7f849c";
  overlay_2 = "#9399b2";
  subtext_0 = "#a6adc8";
  subtext_1 = "#bac2de";

  # Accents
  rosewater = "#f5e0dc";
  flamingo  = "#f2cdcd";
  pink      = "#f5c2e7";
  mauve     = "#cba6f7";
  red       = "#f38ba8";
  maroon    = "#eba0ac";
  peach     = "#fab387";
  yellow    = "#f9e2af";
  green     = "#a6e3a1";
  teal      = "#94e2d5";
  sky       = "#89dceb";
  sapphire  = "#74c7ec";
  blue      = "#89b4fa";
  lavender  = "#b4befe";

  # Default icon-foreground for two-tone widgets (contrasts with bright accent bg).
  # On dark palettes this is the darkest surface; on light palettes it stays dark.
  iconFgDefault = "#11111b";

  # Window-status flag icons + colors (Nerd Font glyphs)
  flags = {
    active   = { icon = "󰮯"; color = "#a6e3a1"; };  # green
    last     = { icon = "󰮏"; color = "#a6adc8"; };  # subtext_0
    zoomed   = { icon = "󰊓"; color = "#fab387"; };  # peach
    bell     = { icon = "󰂜"; color = "#f38ba8"; };  # red
    activity = { icon = "󰐱"; color = "#f9e2af"; };  # yellow
    silence  = { icon = "󰒲"; color = "#6c7086"; };  # overlay_0
  };
}
