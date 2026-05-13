# cpu — usage percentage (macOS top -l 1 / Linux /proc/stat deltas).
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-cpu";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.procps ];
    text = builtins.readFile ./scripts/cpu.sh;
  };
  cached = cache.wrap { name = "tmux-widget-cpu"; seconds = 5; script = raw; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󱦘 ";   # nf-md-cpu-64-bit
    ascii    = "[%] ";
    emoji    = "⚙️ ";
    none     = "";
  };
  iconBg = palette.red;
  text   = " #(${cached}/bin/tmux-widget-cpu-cached) ";
  inherit style;
}
