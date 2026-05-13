# uptime — system uptime pretty-printed.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-uptime";
    runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.procps ];
    text = builtins.readFile ./scripts/uptime.sh;
  };
  cached = cache.wrap { name = "tmux-widget-uptime"; seconds = 60; script = raw; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰔟 ";   # nf-md-timer-sand
    ascii    = "[U] ";
    emoji    = "⏱ ";
    none     = "";
  };
  iconBg = palette.lavender;
  text   = " #(${cached}/bin/tmux-widget-uptime-cached) ";
  inherit style;
}
