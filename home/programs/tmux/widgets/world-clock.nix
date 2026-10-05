# world-clock — extra time zones next to the local clock.
#
# tmux's native strftime (`%R` in date-time.nix) only knows the server's TZ,
# so other zones need a `#()` fork: `TZ=<zone> date`. Uncached: `date` is
# cheap and a cache would show stale minutes.
#
# Zones are IANA names (not "EST"/"PST") so DST is handled by tzdata and
# %Z flips EST↔EDT / PST↔PDT automatically.
{ lib, pkgs, palette, icons, style
, zones ? [ "America/New_York" "America/Los_Angeles" ]
, format ? "%H:%M %Z"
}:
let
  base = import ./_base.nix { inherit lib; };

  scriptText = lib.replaceStrings
    [ "@ZONES@" "@FORMAT@" ]
    [ (lib.concatStringsSep " " zones) format ]
    (builtins.readFile ./scripts/world-clock.sh);

  raw = pkgs.writeShellApplication {
    name = "tmux-widget-world-clock";
    # tzdata via TZDIR so `TZ=America/New_York` resolves on any host
    # (macOS has /usr/share/zoneinfo; minimal Linux containers may not).
    runtimeInputs = [ pkgs.coreutils ];
    runtimeEnv = { TZDIR = "${pkgs.tzdata}/share/zoneinfo"; };
    text = scriptText;
  };
in
base.defaults palette // {
  # No icon — same plain presentation as date-time; zone abbreviations
  # identify each clock.
  icon   = "";
  iconBg = palette.mauve;
  iconFg = palette.crust;
  text   = " #(${raw}/bin/tmux-widget-world-clock) ";
  inherit style;
  skipWhenEmpty = true;
}
