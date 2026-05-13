#!/usr/bin/env bash
# Print count of clients attached to the current tmux server.
# Reference: Dracula's attached_clients.sh (behavior only — code is fresh).
count=$(tmux list-clients 2>/dev/null | wc -l | tr -d ' ')
[ -z "$count" ] && count=0
printf '%s' "$count"
