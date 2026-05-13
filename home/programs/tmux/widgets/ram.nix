# ram — memory used percentage (macOS vm_stat / Linux /proc/meminfo).
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-ram";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.gnused ];
    text = builtins.readFile ./scripts/ram.sh;
  };
  cached = cache.wrap { name = "tmux-widget-ram"; seconds = 5; script = raw; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰍛 ";   # nf-md-memory
    ascii    = "[M] ";
    emoji    = "💾 ";
    none     = "";
  };
  iconBg = palette.maroon;
  text   = " #(${cached}/bin/tmux-widget-ram-cached) ";
  inherit style;
}
