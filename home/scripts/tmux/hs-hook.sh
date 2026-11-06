#!/bin/sh
# Hubstaff project switcher — called by tmux client-session-changed hook.
# Defensive wrapper: debounces rapid session switches, kills stale instances,
# and never blocks tmux longer than 2 seconds total.
#
# Debounce strategy: write a nanosecond-precision timestamp; skip if the last
# switch was < 2s ago. This handles the tmuxp bulk-load storm (many sessions
# created in <1s) that the old 1s integer debounce missed.

SESSION="$1"
HS=/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI
LOCK="/tmp/hs-hook.lock"
DEBOUNCE_FILE="/tmp/hs-hook-last"
DEBOUNCE_MS=2000  # milliseconds between allowed invocations

# --- Debounce: skip if another switch happened within DEBOUNCE_MS ---
# Use python for sub-second precision (date +%N is GNU-only, not on macOS).
now_ms=$(/usr/bin/python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
if [ -f "$DEBOUNCE_FILE" ]; then
  last_ms=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
  elapsed=$((now_ms - last_ms))
  if [ "$elapsed" -ge 0 ] && [ "$elapsed" -lt "$DEBOUNCE_MS" ]; then
    exit 0
  fi
fi
printf '%s' "$now_ms" > "$DEBOUNCE_FILE"

# --- Single-instance: kill any prior hook still running ---
if [ -f "$LOCK" ]; then
  old_pid=$(cat "$LOCK" 2>/dev/null)
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null
  fi
fi
printf '%s' "$$" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# --- Check Hubstaff with a 1s timeout ---
if ! timeout 5 "$HS" send status >/dev/null 2>&1; then
  # Not running. Try to start it, but don't block tmux for it.
  open -a Hubstaff 2>/dev/null
  # Give it one quick check after 1s, then give up
  sleep 1
  if ! timeout 5 "$HS" send status >/dev/null 2>&1; then
    tmux display-message "HS: Hubstaff not ready -- will catch next switch"
    exit 0
  fi
fi

# --- Switch project with a 1s timeout ---
case "$SESSION" in
  CELL)  timeout 5 "$HS" send start-project --project_id 4165404 >/dev/null 2>&1 ;;
  DIMM)  timeout 5 "$HS" send start-project --project_id 3956770 >/dev/null 2>&1 ;;
  EVER)  timeout 5 "$HS" send start-project --project_id 3956768 >/dev/null 2>&1 ;;
  FAM)   timeout 5 "$HS" send start-project --project_id 3979460 >/dev/null 2>&1 ;;
  FINA)  timeout 5 "$HS" send start-project --project_id 3979461 >/dev/null 2>&1 ;;
  HERI)  timeout 5 "$HS" send start-project --project_id 3979462 >/dev/null 2>&1 ;;
  HOME)  timeout 5 "$HS" send start-project --project_id 3727679 >/dev/null 2>&1 ;;
  HZL)   timeout 5 "$HS" send start-project --project_id 3497760 >/dev/null 2>&1 ;;
  I)     timeout 5 "$HS" send start-project --project_id 4097848 >/dev/null 2>&1 ;;
  IMI)   timeout 5 "$HS" send start-project --project_id 4205957 >/dev/null 2>&1 ;;
  IOT)   timeout 5 "$HS" send start-project --project_id 3984316 >/dev/null 2>&1 ;;
  KIRR)  timeout 5 "$HS" send start-project --project_id 3956771 >/dev/null 2>&1 ;;
  KIWA)  timeout 5 "$HS" send start-project --project_id 3979463 >/dev/null 2>&1 ;;
  MAD)   timeout 5 "$HS" send start-project --project_id 3979464 >/dev/null 2>&1 ;;
  MAP)   timeout 5 "$HS" send start-project --project_id 3497711 >/dev/null 2>&1 ;;
  MISKA) timeout 5 "$HS" send start-project --project_id 1751709 >/dev/null 2>&1 ;;
  MUS)   timeout 5 "$HS" send start-project --project_id 4243078 >/dev/null 2>&1 ;;
  NMD)   timeout 5 "$HS" send start-project --project_id 3736729 >/dev/null 2>&1 ;;
  NPT)   timeout 5 "$HS" send start-project --project_id 3497712 >/dev/null 2>&1 ;;
  PTC)   timeout 5 "$HS" send start-project --project_id 3979459 >/dev/null 2>&1 ;;
  UPE)   timeout 5 "$HS" send start-project --project_id 3956769 >/dev/null 2>&1 ;;
  *)
    timeout 5 "$HS" send start-project --project_id 4256427 >/dev/null 2>&1
    tmux display-message "HS: no mapping for [$SESSION] — tracking on ALL project"
    ;;
esac
