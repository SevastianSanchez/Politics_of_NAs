#!/usr/bin/env bash
# What is running right now, and what is stale.
#
#   bash code/runs.sh          what is running, plus the last line of each log
#   bash code/runs.sh -v       also print the last 8 lines of each log
#   bash code/runs.sh --kill   kill everything listed as STALE or ORPHAN (asks first)
#
# Two failure modes this exists to catch:
#   STALE   a fit still running long after it was superseded or abandoned
#   ORPHAN  a parallel worker whose parent died; it keeps a core pinned forever

set -uo pipefail
VERBOSE=0; DOKILL=0
for a in "$@"; do
  case "$a" in
    -v|--verbose) VERBOSE=1 ;;
    --kill)       DOKILL=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

STALE_HOURS=${STALE_HOURS:-6}
LOGGLOB="/private/tmp/claude-501/-Users-sevastiansanchez-Documents-GitHub-Politics-of-NAs/*/scratchpad"

# elapsed as [[dd-]hh:]mm:ss -> seconds
secs() {
  local e=$1 d=0 h=0 m=0 s=0
  case "$e" in *-*) d=${e%%-*}; e=${e#*-} ;; esac
  local n; n=$(awk -F: '{print NF}' <<<"$e")
  case "$n" in
    3) h=${e%%:*}; m=$(cut -d: -f2 <<<"$e"); s=${e##*:} ;;
    2) m=${e%%:*}; s=${e##*:} ;;
    *) s=$e ;;
  esac
  echo $(( 10#$d*86400 + 10#$h*3600 + 10#$m*60 + 10#$s ))
}

printf '%s\n' "----------------------------------------------------------------------"
printf '%-7s %-7s %-10s %6s  %-28s %s\n' PID PARENT ELAPSED 'CPU%' SCRIPT STATUS
printf '%s\n' "----------------------------------------------------------------------"

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
ps -axo pid=,ppid=,etime=,pcpu=,command= | grep '[e]xec/R' > "$TMP" || true

n=0; nbad=0; : > "$TMP.kill"
while read -r pid ppid etime cpu rest; do
  [ -z "${pid:-}" ] && continue
  n=$((n+1))
  script=$(sed -n 's/.*--file=//p' <<<"$rest"); script=${script##*/}
  [ -z "$script" ] && script="(interactive)"
  age=$(secs "$etime")
  status="running"
  if [ "$ppid" = "1" ] && [ "$(cut -d. -f1 <<<"$cpu")" -gt 5 ] 2>/dev/null; then
    status="ORPHAN  no parent"; nbad=$((nbad+1)); echo "$pid" >> "$TMP.kill"
  elif [ "$age" -gt $(( STALE_HOURS * 3600 )) ]; then
    status="STALE   over ${STALE_HOURS}h"; nbad=$((nbad+1)); echo "$pid" >> "$TMP.kill"
  fi
  printf '%-7s %-7s %-10s %6s  %-28s %s\n' "$pid" "$ppid" "$etime" "$cpu" "$script" "$status"
done < "$TMP"

[ "$n" = 0 ] && echo "  nothing running"
printf '%s\n' "----------------------------------------------------------------------"
printf '%d R process(es)' "$n"
[ "$nbad" -gt 0 ] && printf '  --  %d need attention' "$nbad"
echo; echo "load:$(uptime | sed 's/.*load averages*://')"
pmset -g batt 2>/dev/null | awk 'NR==2{sub(/^[^)]*\)[[:space:]]*/,""); sub(/[[:space:]]*present:.*$/,""); print "battery: " $0}'

echo
echo "LOGS  (last ${LOG_HOURS:-6}h; -v for more lines and a full day)"
printf '%s\n' "----------------------------------------------------------------------"
LOG_MINS=$(( ${LOG_HOURS:-6} * 60 )); [ "$VERBOSE" = 1 ] && LOG_MINS=1440
# which log file each live process is writing to (fd 1), so no name guessing
livelogs=""
for lp in $(awk '{print $1}' "$TMP"); do
  lf=$(lsof -p "$lp" -a -d 1 -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  [ -n "$lf" ] && livelogs="$livelogs${lf##*/}
"
done
found=0
for f in $(ls -t $LOGGLOB/*.log 2>/dev/null); do
  age=$(( ($(date +%s) - $(stat -f %m "$f")) / 60 ))
  [ "$age" -gt "$LOG_MINS" ] && continue
  found=1
  base=${f##*/}
  if   grep -qE 'Error|Execution halted|Killed' "$f";                        then state="ERROR"
  elif grep -qE '^\[.*\] done\.' "$f";                                       then state="done"
  elif grep -qxF "$base" <<<"$livelogs";                                     then state="LIVE"
  else                                                                            state="stopped"
  fi
  printf '\n%-8s %4sm ago  %s\n' "$state" "$age" "$base"
  if [ "$VERBOSE" = 1 ]; then tail -8 "$f" | sed 's/^/    /'; else tail -1 "$f" | sed 's/^/    /'; fi
done
[ "$found" = 0 ] && echo "  no logs touched in the last ${LOG_HOURS:-6}h"

if [ "$DOKILL" = 1 ] && [ -s "$TMP.kill" ]; then
  echo; echo "about to kill: $(tr '\n' ' ' < "$TMP.kill")"
  read -r -p "proceed? [y/N] " yn
  case "$yn" in [yY]*) xargs kill < "$TMP.kill" && echo "killed." ;; *) echo "left alone." ;; esac
fi
rm -f "$TMP.kill"
