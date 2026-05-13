# battery — percentage + state icon (macOS pmset / Linux sysfs).
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-battery";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
    text = builtins.readFile ./scripts/battery.sh;
  };
  cached = cache.wrap { name = "tmux-widget-battery"; seconds = 30; script = raw; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰁹 ";   # nf-md-battery
    ascii    = "[B] ";
    emoji    = "🔋 ";
    none     = "";
  };
  iconBg = palette.green;
  text   = " #(${cached}/bin/tmux-widget-battery-cached) ";
  inherit style;
}
