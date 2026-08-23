#!/bin/sh
SESSION="$1"
HS=/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI

if ! "$HS" send status >/dev/null 2>&1; then
  open -a Hubstaff
  for i in 1 2 3 4 5; do
    sleep 1
    "$HS" send status >/dev/null 2>&1 && break
  done
  if ! "$HS" send status >/dev/null 2>&1; then
    tmux display-message "HS: Hubstaff failed to start after 5s"
    exit 0
  fi
fi

case "$SESSION" in
  CELL)  "$HS" send start-project --project_id 4165404 >/dev/null 2>&1 ;;
  DIMM)  "$HS" send start-project --project_id 3956770 >/dev/null 2>&1 ;;
  EVER)  "$HS" send start-project --project_id 3956768 >/dev/null 2>&1 ;;
  FAM)   "$HS" send start-project --project_id 3979460 >/dev/null 2>&1 ;;
  FINA)  "$HS" send start-project --project_id 3979461 >/dev/null 2>&1 ;;
  HERI)  "$HS" send start-project --project_id 3979462 >/dev/null 2>&1 ;;
  HOME)  "$HS" send start-project --project_id 3727679 >/dev/null 2>&1 ;;
  HZL)   "$HS" send start-project --project_id 3497760 >/dev/null 2>&1 ;;
  I)     "$HS" send start-project --project_id 4097848 >/dev/null 2>&1 ;;
  IOT)   "$HS" send start-project --project_id 3984316 >/dev/null 2>&1 ;;
  KIRR)  "$HS" send start-project --project_id 3956771 >/dev/null 2>&1 ;;
  KIWA)  "$HS" send start-project --project_id 3979463 >/dev/null 2>&1 ;;
  MAD)   "$HS" send start-project --project_id 3979464 >/dev/null 2>&1 ;;
  MAP)   "$HS" send start-project --project_id 3497711 >/dev/null 2>&1 ;;
  MISKA) "$HS" send start-project --project_id 1751709 >/dev/null 2>&1 ;;
  NMD)   "$HS" send start-project --project_id 3736729 >/dev/null 2>&1 ;;
  NPT)   "$HS" send start-project --project_id 3497712 >/dev/null 2>&1 ;;
  PTC)   "$HS" send start-project --project_id 3979459 >/dev/null 2>&1 ;;
  UPE)   "$HS" send start-project --project_id 3956769 >/dev/null 2>&1 ;;
  *)
    "$HS" send stop >/dev/null 2>&1
    tmux display-message "HS: no project mapped for session [$SESSION] — tracking stopped"
    ;;
esac
