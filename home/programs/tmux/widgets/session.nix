# session — current tmux session name + prefix indicator.
#
# Color flips red when the prefix key is pressed (visual feedback for chord input).
# Mirrors Catppuccin's behavior: `#{?client_prefix,red,green}` accent.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  # Screen 8 reference: solid green block with dark text — no icon.
  # Composer's icon == "" branch collapses to single block, using iconFg
  # (default = crust, near-black) as text color on the green bg.
  icon   = "";
  # Green by default; flip to red when prefix is active (chord-input feedback).
  iconBg = "#{?client_prefix,${palette.red},${palette.green}}";
  text   = " #S ";
  inherit style;
}
