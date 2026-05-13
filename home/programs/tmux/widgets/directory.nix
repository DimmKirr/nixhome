# directory — basename of the current pane's working directory.
#
# Uses tmux's `#{b:...}` format modifier — no shell fork.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰉋 ";   # nf-md-folder
    ascii    = "[D] ";
    emoji    = "📁 ";
    none     = "";
  };
  iconBg = palette.peach;     # warm — "where you are"
  text   = " #{b:pane_current_path} ";
  inherit style;
}
