#!/usr/bin/env bash
#
# catch-loader.sh — catch the fileless worm loader at the instant it spawns.
#
# The worm's workers (node -e global['...) are fileless, but whatever SPAWNS
# them is a real process with a real file + cwd. This watcher polls fast and,
# the moment a worker appears, snapshots its full ancestor chain (pid, parent
# command, cwd, open script) to a log — revealing the source.
#
# Usage:
#   ./catch-loader.sh              # watch, log, leave workers running
#   ./catch-loader.sh --kill       # watch, log, then kill caught workers
#
# Then, in another terminal, REPRODUCE: run the backend app
# (npm start / nest start / node app.js). When the swarm fires, this logs the
# culprit. Ctrl-C to stop. Read the log path printed at start.
#
set -uo pipefail
KILL=0
[[ "${1:-}" == "--kill" || "${1:-}" == "-k" ]] && KILL=1
SELF=$$
LOG="$HOME/loader-catch-$(date +%Y%m%d-%H%M%S).log"

WPAT="node -e global\["
echo "watching for worm loader... log: $LOG"
echo "reproduce now: run the backend app in another terminal. Ctrl-C to stop."
echo "=== catch log $(date) ===" > "$LOG"

seen=""
while true; do
  for w in $(pgrep -f "$WPAT" 2>/dev/null | grep -vx "$SELF"); do
    case " $seen " in *" $w "*) continue;; esac   # already logged
    seen="$seen $w"
    {
      echo "----------------------------------------------"
      echo "[$(date '+%H:%M:%S')] WORKER pid=$w"
      # ancestor chain
      p="$w"
      for i in 1 2 3 4 5 6; do
        [ -z "$p" ] && break; [ "$p" = "1" ] && { echo "  ^ launchd (orphaned)"; break; }
        line=$(ps -o pid,ppid,etime,command -p "$p" 2>/dev/null | tail -1)
        echo "  $line"
        cwd=$(lsof -a -d cwd -p "$p" 2>/dev/null | tail -1 | awk '{print $NF}')
        [ -n "$cwd" ] && echo "       cwd: $cwd"
        # script file the process is executing (first .js in txt/REG)
        scr=$(lsof -p "$p" 2>/dev/null | awk '/\.[cm]?js( |$)/{print $NF; exit}')
        [ -n "$scr" ] && echo "       file: $scr"
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
      done
    } | tee -a "$LOG"
    [ "$KILL" -eq 1 ] && kill -9 "$w" 2>/dev/null && echo "  killed $w" | tee -a "$LOG"
  done
  sleep 0.4
done
