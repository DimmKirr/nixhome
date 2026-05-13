#!/usr/bin/env bash
# CPU usage percentage.
# macOS: top -l 1 parsing; Linux: /proc/stat deltas.

case "$(uname -s)" in
  Darwin)
    # top -l 1 produces a "CPU usage: 8.42% user, 6.41% sys, 85.16% idle" line.
    idle=$(top -l 1 -n 0 2>/dev/null | awk -F'[%, ]+' '/CPU usage/ {for(i=1;i<=NF;i++) if($i=="idle") print $(i-1); exit}')
    if [ -n "$idle" ]; then
      pct=$(awk -v i="$idle" 'BEGIN { printf "%.0f", 100 - i }')
      printf '%s%%' "$pct"
    else
      printf '?%%'
    fi
    ;;
  Linux)
    # Sample /proc/stat twice 200ms apart; compute delta.
    read -r _ a b c idle1 _ < /proc/stat
    sleep 0.2
    read -r _ a2 b2 c2 idle2 _ < /proc/stat
    total1=$((a + b + c + idle1))
    total2=$((a2 + b2 + c2 + idle2))
    dtotal=$((total2 - total1))
    didle=$((idle2 - idle1))
    if [ "$dtotal" -gt 0 ]; then
      pct=$(( (100 * (dtotal - didle)) / dtotal ))
      printf '%s%%' "$pct"
    else
      printf '?%%'
    fi
    ;;
  *)
    printf ''
    ;;
esac
