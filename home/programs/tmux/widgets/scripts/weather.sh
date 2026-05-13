#!/usr/bin/env bash
# Current weather via wttr.in. City + unit baked in at nix eval time via
# @CITY@ / @UNIT@ placeholders — no env-var dependency from tmux.
#
# Output: "<nerd-glyph> <temp> <city>", e.g. "󰖙 73°F NYC".
# Uses wttr.in `%x` (numeric condition code) mapped to nf-md-weather-* glyphs.
# City is appended from the baked variable rather than %l so we control the
# casing/spelling.

city="${TMUX_WIDGET_WEATHER_CITY:-@CITY@}"
unit="${TMUX_WIDGET_WEATHER_UNIT:-@UNIT@}"

url="https://wttr.in"
[ -n "$city" ] && url="$url/$city"
# `_` is a clean separator: URL-safe, never appears in wttr.in's %x (digits)
# or %t ("+73°F"). Bash quoting preserves it literally.
url="${url}?format=%x_%t&${unit}"

result=$(curl -fsSL --max-time 5 "$url" 2>/dev/null || true)

# Reject HTML error pages and empty/whitespace-only responses.
if [ -z "${result// /}" ] || printf '%s' "$result" | grep -q "<"; then
  exit 0
fi

code="${result%%_*}"
temp="${result#*_}"
# wttr.in always prefixes temperature with a sign (+73°F, -5°F). Conventional
# display omits the leading + while preserving -.
temp="${temp#+}"

# Map wttr.in condition code → nerd-font weather glyph.
# Codes: https://www.worldweatheronline.com/developer/api/docs/weather-icons.aspx
case "$code" in
  113)                                          glyph="󰖙" ;;   # Sunny / Clear
  116)                                          glyph="󰖕" ;;   # Partly cloudy
  119|122)                                      glyph="󰖐" ;;   # Cloudy / Overcast
  143|248|260)                                  glyph="󰖑" ;;   # Mist / Fog
  176|263|266|293|296|353)                      glyph="󰼳" ;;   # Light rain / drizzle
  299|302|305|308|356|359)                      glyph="󰖖" ;;   # Moderate-heavy rain
  179|182|185|281|284|311|314|317|320|362|365)  glyph="󰙿" ;;   # Sleet / freezing rain
  227|230|323|326|329|332|335|338|368|371)      glyph="󰖘" ;;   # Snow
  350|374|377)                                  glyph="󰼶" ;;   # Ice pellets / heavy snow
  200|386|389|392|395)                          glyph="󰖓" ;;   # Thunder
  *)                                            glyph="󰖐" ;;   # Fallback: cloudy
esac

if [ -n "$city" ]; then
  printf '%s %s %s' "$glyph" "$temp" "$city"
else
  printf '%s %s' "$glyph" "$temp"
fi
