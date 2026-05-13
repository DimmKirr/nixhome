#!/usr/bin/env bash
# Current wifi SSID. macOS: networksetup; Linux: iwgetid.
# Outputs SSID or "" if not on wifi.

case "$(uname -s)" in
  Darwin)
    ssid=$(networksetup -getairportnetwork en0 2>/dev/null | sed -E 's/^Current Wi-Fi Network: //; /You are not associated/d' || true)
    ;;
  Linux)
    ssid=$(iwgetid -r 2>/dev/null || true)
    ;;
  *)
    ssid=""
    ;;
esac

printf '%s' "$ssid"
