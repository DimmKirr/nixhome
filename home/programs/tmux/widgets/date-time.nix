# date-time — clock widget. Uses tmux's strftime support — no shell fork.
{ lib, pkgs, palette, icons, style, format ? "%R %Z" }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  # No widget icon — matches the original Dracula's plain "17:12 UTC" presentation.
  # Time is its own identifier; an icon adds visual noise without info.
  icon   = "";
  # overlay_0 = Dracula's selection grey #44475A — matches screen 8's time
  # module (dark grey block, same shade as inactive windows).
  iconBg = palette.overlay_0;
  # Composer collapses to single block when icon == "", using iconFg as the
  # text color — override default crust to subtext_0 (light grey).
  iconFg = palette.subtext_0;
  text   = " ${format} ";
  inherit style;
}
