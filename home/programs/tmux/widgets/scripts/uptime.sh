#!/usr/bin/env bash
# Pretty-print system uptime as "Xd Yh Zm".
# Reference: Catppuccin's uptime.conf sed expression (cleaner than Dracula's parsing).
LC_ALL=C uptime \
  | sed -E '
      s/^[^,]*up *//
      s/, *[0-9]+ user.*//
      s/ days?, */d /
      s/ hrs?.*/h/
      s/ mins?.*/m/
      s/ secs?.*/s/
      s/([0-9]{1,2}):([0-9]{1,2})/\1h \2m/
      s/ +$//
    '
