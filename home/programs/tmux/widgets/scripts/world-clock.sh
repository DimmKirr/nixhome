#!/usr/bin/env bash
# Print the current time in each configured IANA zone, e.g. "09:12 EDT  06:12 PDT".
# Zones are baked at Nix eval via @ZONES@ (space-separated IANA names).
# Override at runtime with TMUX_WIDGET_WORLD_CLOCK_ZONES.
# %Z yields the DST-aware abbreviation (EST/EDT, PST/PDT) from tzdata.
zones="${TMUX_WIDGET_WORLD_CLOCK_ZONES:-@ZONES@}"
fmt="@FORMAT@"

out=""
for z in $zones; do
  t="$(TZ="$z" date +"$fmt")" || continue
  out="${out:+$out  }$t"
done
printf '%s' "$out"
