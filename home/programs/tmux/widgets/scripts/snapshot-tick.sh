#!/usr/bin/env bash
# Invisible auto-save tick — fires `tmux-snapshot save-all` when enough time
# has elapsed since the last save. Ported from existing tmux.nix.
#
# Emits nothing to status bar (designed to live in status-right invisibly).
# Config:
#   @snapshot-save-interval (minutes, default 10)
#   @snapshot-last-save     (epoch seconds, persisted across saves)

interval_min=$(tmux show -gqv @snapshot-save-interval 2>/dev/null)
[ -z "$interval_min" ] && interval_min=10
interval=$((interval_min * 60))

last=$(tmux show -gqv @snapshot-last-save 2>/dev/null)
[ -z "$last" ] && last=0

now=$(date +%s)
if [ "$((now - last))" -ge "$interval" ]; then
  if tmux-snapshot save-all >/dev/null 2>&1; then
    tmux set -g @snapshot-last-save "$now"
  fi
fi
# Always emit nothing — this widget is invisible.
