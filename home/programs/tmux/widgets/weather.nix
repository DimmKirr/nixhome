# weather — wttr.in via curl + 10-min cache.
#
# City and unit are baked at Nix eval time (no env-var dependency).
# Override per-call via: framework.renderWidget' "weather" { city = "Madeira"; unit = "m"; }
# (Future enhancement — not implemented yet; framework currently uses defaults.)
{ lib, pkgs, palette, icons, style, city ? "NYC", unit ? "u" }:
let
  base = import ./_base.nix { inherit lib; };
  cache = import ./_cache.nix { inherit pkgs; };

  # Substitute config + icon vocabulary at eval time. `@USE_NERDFONT@` gates
  # whether weather.sh emits PUA Nerd Font glyphs (󰖙 󰖐 …) or plain BMP
  # Unicode (☀ ☁ …) so thin SSH clients without a Nerd Font render correctly.
  # (Ticket: tmux-widgets-emit-stray-escapes-when-empty — "cloud icon" symptom)
  scriptText = lib.replaceStrings
    [ "@CITY@" "@UNIT@" "@USE_NERDFONT@" ]
    [ city unit (if icons == "nerdFont" then "true" else "false") ]
    (builtins.readFile ./scripts/weather.sh);

  raw = pkgs.writeShellApplication {
    name = "tmux-widget-weather";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gnugrep ];
    text = scriptText;
  };
  cached = cache.wrap { name = "tmux-widget-weather"; seconds = 600; script = raw; };
in
base.defaults palette // {
  # No widget icon — weather.sh emits the condition glyph (or omits it under
  # ascii mode). Peach bg matches the original Dracula module color rotation.
  icon   = "";
  iconBg = palette.peach;
  iconFg = palette.crust;
  text   = " #(${cached}/bin/tmux-widget-weather-cached) ";
  inherit style;
  skipWhenEmpty = true;  # offline / curl failure → block disappears entirely
}
