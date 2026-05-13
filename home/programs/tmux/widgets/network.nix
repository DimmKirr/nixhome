# network — current wifi SSID.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-network";
    runtimeInputs = [ pkgs.coreutils pkgs.gnused ];
    text = builtins.readFile ./scripts/network.sh;
  };
  cached = cache.wrap { name = "tmux-widget-network"; seconds = 30; script = raw; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰖩 ";   # nf-md-wifi
    ascii    = "[N] ";
    emoji    = "📶 ";
    none     = "";
  };
  iconBg = palette.flamingo;
  text   = " #(${cached}/bin/tmux-widget-network-cached) ";
  inherit style;
}
