# application — current pane's foreground process name. Catppuccin's idea.
# Uses tmux's native #{pane_current_command} — no shell fork.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰘔 ";   # nf-md-application
    ascii    = "[A] ";
    emoji    = "📦 ";
    none     = "";
  };
  iconBg = palette.teal;
  text   = " #{pane_current_command} ";
  inherit style;
}
