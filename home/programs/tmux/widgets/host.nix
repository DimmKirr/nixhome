# host — show the hostname.
#
# Static (no shell command) — tmux's `#H` interpolation gives the hostname
# directly. Cheap, no fork.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰒋 ";   # nf-md-server
    ascii    = "[H] ";
    emoji    = "💻 ";
    none     = "";
  };
  iconBg = palette.mauve;     # purple accent for "system identity" widgets
  text   = " #H ";            # tmux format string — leading/trailing space for breathing room
  inherit style;
}
