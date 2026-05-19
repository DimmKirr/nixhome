# session — current tmux session name + prefix indicator.
#
# Color flips yellow when the prefix key is pressed (visual feedback for chord
# input). Matches the original Dracula tmux plugin's `dracula-show-prefix`
# behavior — Catppuccin uses red, Dracula uses yellow.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  # Screen 8 reference: solid green block with dark text — no icon.
  # Composer's icon == "" branch collapses to single block, using iconFg
  # (default = crust, near-black) as text color on the green bg.
  icon   = "";
  # Green by default; flip to yellow when prefix is active (chord-input
  # feedback). Matches pre-framework Dracula plugin behavior.
  iconBg = "#{?client_prefix,${palette.yellow},${palette.green}}";
  text   = " #S ";
  inherit style;
}
