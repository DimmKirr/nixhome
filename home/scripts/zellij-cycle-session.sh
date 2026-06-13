#!/usr/bin/env bash
# Cycle to next/previous zellij session by name order.
# Usage: zellij-cycle-session.sh [next|prev]
# Must be called from inside a zellij session.
set -euo pipefail

direction="${1:-next}"

mapfile -t sessions < <(zellij list-sessions --short --no-formatting | sort)
count=${#sessions[@]}
[[ $count -le 1 ]] && exit 0

current=$(zellij list-sessions --no-formatting | grep '(current)' | awk '{print $1}')
[[ -z "$current" ]] && exit 0

idx=-1
for i in "${!sessions[@]}"; do
  [[ "${sessions[$i]}" == "$current" ]] && { idx=$i; break; }
done
[[ $idx -eq -1 ]] && exit 0

if [[ "$direction" == "next" ]]; then
  target_idx=$(( (idx + 1) % count ))
else
  target_idx=$(( (idx - 1 + count) % count ))
fi

zellij action switch-session "${sessions[$target_idx]}"
