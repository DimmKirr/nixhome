# snapshot-tick — invisible status-right tick that auto-saves the tmux session.
# Special widget: emits no visible output. Always uses `minimal` style regardless
# of theme so it doesn't render colored blocks.
{ lib, pkgs, palette, icons, style }:
let
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-snapshot-tick";
    runtimeInputs = [ pkgs.coreutils pkgs.tmux ];
    text = builtins.readFile ./scripts/snapshot-tick.sh;
  };
in
{
  icon = "";
  iconFg = "default";
  iconBg = "default";
  text = "#(${raw}/bin/tmux-widget-snapshot-tick)";
  textFg = "default";
  textBg = "default";
  style = "minimal";   # always minimal — invisible widget
}
