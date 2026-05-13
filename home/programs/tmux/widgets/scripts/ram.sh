#!/usr/bin/env bash
# RAM usage as percentage.
# macOS: vm_stat (pages of 16KB); Linux: /proc/meminfo.

case "$(uname -s)" in
  Darwin)
    # vm_stat returns pages; page size is usually 16384 on Apple Silicon.
    stats=$(vm_stat 2>/dev/null || true)
    [ -z "$stats" ] && { printf ''; exit 0; }
    page=$(printf '%s' "$stats" | sed -n 's/Mach Virtual Memory Statistics:.*(page size of \([0-9]*\) bytes).*/\1/p')
    [ -z "$page" ] && page=16384
    get() { printf '%s' "$stats" | awk -v k="$1" '$0 ~ k {gsub("[^0-9]","",$NF); print $NF; exit}'; }
    free=$(get "Pages free")
    active=$(get "Pages active")
    inactive=$(get "Pages inactive")
    wired=$(get "Pages wired down")
    compressed=$(get "Pages occupied by compressor")
    total=$((free + active + inactive + wired + compressed))
    used=$((active + wired + compressed))
    if [ "$total" -gt 0 ]; then
      pct=$(( 100 * used / total ))
      printf '%s%%' "$pct"
    else
      printf '?%%'
    fi
    ;;
  Linux)
    total=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
    avail=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)
    if [ -n "$total" ] && [ -n "$avail" ] && [ "$total" -gt 0 ]; then
      used=$((total - avail))
      pct=$(( 100 * used / total ))
      printf '%s%%' "$pct"
    else
      printf '?%%'
    fi
    ;;
  *)
    printf ''
    ;;
esac
