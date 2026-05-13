# user — show $USER (or whoami fallback). Catppuccin's idea.
# Uses tmux's #(whoami) — no caching needed (called per status tick but trivial).
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = " ";    # nf-fa-user
    ascii    = "[U] ";
    emoji    = "👤 ";
    none     = "";
  };
  iconBg = palette.sky;
  text   = " #(whoami) ";
  inherit style;
}
