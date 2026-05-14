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

# Map wttr.in condition code → glyph. Two sets:
#   nerdFont  — Nerd Font PUA glyphs (nf-md-weather-*) — pretty on terminals
#               with a Nerd Font; renders as tofu boxes on Termius/JuiceSSH/
#               PuTTY without one.
#   ascii     — empty (no glyph) — guaranteed-portable. The `73°F NYC` text
#               is identifier enough; an icon is decorative.
# Codes: https://www.worldweatheronline.com/developer/api/docs/weather-icons.aspx
# `@USE_NERDFONT@` is substituted to literal "true" or "false" at nix eval.
# shellcheck disable=SC2050  # constant by design — value differs per Nix build
if [ "@USE_NERDFONT@" = "true" ]; then
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
else
  # ASCII mode: use BMP-Unicode weather glyphs. All chars are in the Basic
  # Multilingual Plane (U+0000–U+FFFF) below the Private Use Area, so they
  # render on every system font — no Nerd Font required. Renders correctly
  # in Termius, JuiceSSH, PuTTY, Blink, and macOS Terminal.app.
  case "$code" in
    113)                                          glyph="☀" ;;   # U+2600  Sunny / Clear
    116)                                          glyph="⛅" ;;   # U+26C5  Partly cloudy
    119|122)                                      glyph="☁" ;;   # U+2601  Cloudy / Overcast
    143|248|260)                                  glyph="≈" ;;   # U+2248  Mist / Fog
    176|263|266|293|296|353)                      glyph="☂" ;;   # U+2602  Light rain / drizzle
    299|302|305|308|356|359)                      glyph="☔" ;;   # U+2614  Heavy rain
    179|182|185|281|284|311|314|317|320|362|365)  glyph="❅" ;;   # U+2745  Sleet / freezing
    227|230|323|326|329|332|335|338|368|371)      glyph="❄" ;;   # U+2744  Snow
    350|374|377)                                  glyph="❄" ;;   # U+2744  Ice / heavy snow
    200|386|389|392|395)                          glyph="⚡" ;;   # U+26A1  Thunderstorm
    *)                                            glyph="☁" ;;   # Fallback: cloudy
  esac
fi

# Strip any embedded newlines/CR/BEL that wttr.in might inject under odd
# locale conditions — prevents secret-newline breakage of the status row.
# (Ticket: tmux-widgets-emit-stray-escapes-when-empty)
clean() { printf '%s' "$1" | tr -d '\n\r\a'; }
glyph=$(clean "$glyph")
temp=$(clean "$temp")
city=$(clean "$city")

if [ -n "$glyph" ] && [ -n "$city" ]; then
  printf '%s %s %s' "$glyph" "$temp" "$city"
elif [ -n "$glyph" ]; then
  printf '%s %s' "$glyph" "$temp"
elif [ -n "$city" ]; then
  printf '%s %s' "$temp" "$city"
else
  printf '%s' "$temp"
fi
