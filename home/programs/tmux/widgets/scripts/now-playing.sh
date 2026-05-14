#!/usr/bin/env bash
# now-playing wrapper. Calls upstream music.sh and prints PLAIN TEXT only —
# the framework composer draws the cyan bg block around it. Returns empty
# when no player is running; the composer's `skipWhenEmpty = true` then
# collapses the whole block (including bg) via tmux's #{?#{==:...},,...} guard.
#
# @MUSIC_SCRIPT@ is substituted at nix eval time.

out="$("@MUSIC_SCRIPT@" 2>/dev/null || true)"

# Trim leading/trailing whitespace AND strip embedded newlines/CR/BEL that
# music.sh can occasionally produce when track metadata has unusual chars.
# Embedded control chars in status-right break the 2-row layout — they wrap
# content onto a phantom third line.
# (Ticket: tmux-widgets-emit-stray-escapes-when-empty — "secret newline" symptom)
trimmed="${out#"${out%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
trimmed="${trimmed//$'\n'/ }"
trimmed="${trimmed//$'\r'/ }"
trimmed="${trimmed//$'\a'/}"

[ -z "$trimmed" ] && exit 0

printf '%s' "$trimmed"
