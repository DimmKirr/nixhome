#!/usr/bin/env bash
# Battery percentage + charging indicator.
# macOS: pmset; Linux: /sys/class/power_supply.
# Output format: "[icon] PCT%" where icon = charging/discharging/full.

case "$(uname -s)" in
  Darwin)
    out=$(pmset -g batt 2>/dev/null || echo "")
    pct=$(printf '%s' "$out" | grep -Eo '[0-9]+%' | head -1)
    state=$(printf '%s' "$out" | grep -oE 'charging|discharging|charged|AC attached' | head -1)
    ;;
  Linux)
    cap_file=$(ls /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    [ -z "$cap_file" ] && { printf ''; exit 0; }
    pct="$(cat "$cap_file")%"
    status_file="${cap_file%/capacity}/status"
    state=$(cat "$status_file" 2>/dev/null || echo "")
    case "$state" in
      Charging)    state="charging" ;;
      Discharging) state="discharging" ;;
      Full)        state="charged" ;;
      *)           state="" ;;
    esac
    ;;
  *)
    printf ''
    exit 0
    ;;
esac

# Pick icon based on state
case "$state" in
  charging|"AC attached") icon='󰂄' ;;   # battery-charging
  charged)                icon='󰁹' ;;   # battery-full
  discharging|*)          icon='󰁾' ;;   # battery-50 (generic)
esac

[ -n "$pct" ] && printf '%s %s' "$icon" "$pct" || printf ''
