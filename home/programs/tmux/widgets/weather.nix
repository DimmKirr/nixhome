# weather — wttr.in via curl + 10-min cache.
#
# City and unit are baked at Nix eval time (no env-var dependency).
# Override per-call via: framework.renderWidget' "weather" { city = "Madeira"; unit = "m"; }
# (Future enhancement — not implemented yet; framework currently uses defaults.)
{ lib, pkgs, palette, icons, style, city ? "NYC", unit ? "u" }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };

  # Substitute @CITY@ / @UNIT@ at eval time so the script has its config
  # baked in — no dependence on tmux passing env vars to #() subprocesses.
  scriptText = lib.replaceStrings
    [ "@CITY@" "@UNIT@" ]
    [ city unit ]
    (builtins.readFile ./scripts/weather.sh);

  raw = pkgs.writeShellApplication {
    name = "tmux-widget-weather";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gnugrep ];
    text = scriptText;
  };
  cached = cache.wrap { name = "tmux-widget-weather"; seconds = 600; script = raw; };
in
base.defaults palette // {
  # No widget icon — weather.sh outputs its own %c emoji from wttr.in.
  # Peach bg matches the original Dracula module color rotation.
  icon   = "";
  iconBg = palette.peach;
  text   = " #(${cached}/bin/tmux-widget-weather-cached) ";
  inherit style;
}
