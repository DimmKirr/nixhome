#!/bin/sh
SESSION="$1"
HS=/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI

if ! "$HS" status >/dev/null 2>&1; then
  open -a Hubstaff
  for i in 1 2 3 4 5; do
    sleep 1
    "$HS" status >/dev/null 2>&1 && break
  done
  if ! "$HS" status >/dev/null 2>&1; then
    tmux display-message "HS: Hubstaff failed to start after 5s"
    exit 0
  fi
fi

case "$SESSION" in
  DIMM) "$HS" start_project 3956770 >/dev/null 2>&1 ;;
  EVER) "$HS" start_project 3956768 >/dev/null 2>&1 ;;
  FAM)  "$HS" start_project 3979460 >/dev/null 2>&1 ;;
  FINA) "$HS" start_project 3979461 >/dev/null 2>&1 ;;
  HERI) "$HS" start_project 3979462 >/dev/null 2>&1 ;;
  HOME) "$HS" start_project 3727679 >/dev/null 2>&1 ;;
  HZL)  "$HS" start_project 3497760 >/dev/null 2>&1 ;;
  KIRR) "$HS" start_project 3956771 >/dev/null 2>&1 ;;
  KIWA) "$HS" start_project 3979463 >/dev/null 2>&1 ;;
  MAD)  "$HS" start_project 3979464 >/dev/null 2>&1 ;;
  MAP)  "$HS" start_project 3497711 >/dev/null 2>&1 ;;
  NMD)  "$HS" start_project 3736729 >/dev/null 2>&1 ;;
  NPT)  "$HS" start_project 3497712 >/dev/null 2>&1 ;;
  PTC)  "$HS" start_project 3979459 >/dev/null 2>&1 ;;
  UPE)  "$HS" start_project 3956769 >/dev/null 2>&1 ;;
  *)
    "$HS" stop >/dev/null 2>&1
    tmux display-message "HS: no project mapped for session [$SESSION] — tracking stopped"
    ;;
esac
