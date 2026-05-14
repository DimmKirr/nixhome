# date-time — clock widget. Uses tmux's strftime support — no shell fork.
{ lib, pkgs, palette, icons, style, format ? "%R %Z" }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  # No widget icon — matches the original Dracula's plain "17:12 UTC" presentation.
  # Time is its own identifier; an icon adds visual noise without info.
  icon   = "";
  # overlay_2 = Dracula's "comment" #6272A4 — distinct shade from inactive
  # window blocks (overlay_0 #44475A), so the time block is visually separate
  # from the surrounding windows. Matches the pre-framework Dracula plugin's
  # rendering. Catppuccin maps overlay_2 to a similar mid-tone.
  # (Ticket: tmux-dracula-palette-diverges-from-upstream)
  iconBg = palette.overlay_2;
  # Composer collapses to single block when icon == "", using iconFg as the
  # text color — fg gives high contrast on the overlay_2 bg.
  iconFg = palette.fg;
  text   = " ${format} ";
  inherit style;
}
