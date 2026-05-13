# attached-clients — count of tmux clients attached to this server.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  script = pkgs.writeShellApplication {
    name = "tmux-widget-attached-clients";
    runtimeInputs = [ pkgs.coreutils pkgs.tmux ];
    text = builtins.readFile ./scripts/attached-clients.sh;
  };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = "󰣀 ";   # nf-md-account-multiple
    ascii    = "[C] ";
    emoji    = "👥 ";
    none     = "";
  };
  iconBg = palette.sapphire;
  text   = " #(${script}/bin/tmux-widget-attached-clients) ";
  inherit style;
}
