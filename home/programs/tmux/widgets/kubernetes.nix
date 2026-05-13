# kubernetes — current kubectl context + namespace.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-kubernetes";
    runtimeInputs = [ pkgs.coreutils pkgs.kubectl ];
    text = builtins.readFile ./scripts/kubernetes.sh;
  };
  cached = cache.wrap { name = "tmux-widget-kubernetes"; seconds = 10; script = raw; };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󱃾 ";   # nf-md-kubernetes
    ascii    = "[K] ";
    emoji    = "☸ ";
    none     = "";
  };
  iconBg = palette.blue;
  text   = " #(${cached}/bin/tmux-widget-kubernetes-cached) ";
  inherit style;
}
