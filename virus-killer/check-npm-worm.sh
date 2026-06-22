#!/usr/bin/env bash
#
# check-npm-worm.sh — detect, kill, and heal the npm cli.js supply-chain worm
# Incident: 2026-06-21. Worm trojanizes npm's lib/cli.js with an obfuscated
# payload (marker: global['e']='NPM'), spawns hundreds of `node -e` workers,
# and beacons to cloud C2. This script is idempotent and safe to run anytime.
#
# Usage:
#   ./check-npm-worm.sh          # detect + report only
#   ./check-npm-worm.sh --kill   # also kill workers + heal/relock cli.js
#
set -uo pipefail

KILL=0
[[ "${1:-}" == "--kill" || "${1:-}" == "-k" ]] && KILL=1

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
grn()   { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()   { printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
hr()    { printf '%.0s-' {1..56}; echo; }

SIG="global['e']='NPM'"          # payload marker
INFECTED=0                        # overall verdict (0 clean / 1 infected)
SELF=$$

# Real workers run:  node -e global['_V']=...  /  global['e']=...
# The '[' makes the pattern precise so it can't match the checker,
# editors, claude, or shells. Exclude our own pid as belt-and-suspenders.
list_workers() { pgrep -f "node -e global\[" 2>/dev/null | grep -vx "$SELF"; }
list_npmw()    { pgrep -f "npm install.*socket.io-client" 2>/dev/null | grep -vx "$SELF"; }

bold "=== npm worm check  ($(date '+%Y-%m-%d %H:%M:%S')) ==="
hr

# ----------------------------------------------------------------------
# 1. Runtime indicators: load average + worker swarm
# ----------------------------------------------------------------------
load1=$(uptime | sed -E 's/.*load averages?: *([0-9.]+).*/\1/')
workers=$(list_workers | wc -l | tr -d ' ')
npmw=$(list_npmw | wc -l | tr -d ' ')

echo "load (1m):              $load1"
echo "obfuscated workers:     $workers   (expected 0)"
echo "worm npm-install procs: $npmw   (expected 0)"

if [[ "$workers" -gt 0 || "$npmw" -gt 0 ]]; then
  red ">> ACTIVE INFECTION: worm processes running"
  INFECTED=1
fi
# crude load alarm (worm pins load into the hundreds)
if awk "BEGIN{exit !($load1 > 50)}"; then
  ylw ">> load is very high ($load1) — check top consumers"
fi
hr

# ----------------------------------------------------------------------
# 2. File integrity: scan every npm cli.js (all nvm versions + globals)
# ----------------------------------------------------------------------
CLIS=()
while IFS= read -r f; do CLIS+=("$f"); done < <(
  { ls -1 "$HOME"/.nvm/versions/node/*/lib/node_modules/npm/lib/cli.js \
        /usr/local/lib/node_modules/npm/lib/cli.js \
        /opt/homebrew/lib/node_modules/npm/lib/cli.js 2>/dev/null; } | sort -u
)

if [[ ${#CLIS[@]} -eq 0 ]]; then
  ylw "no npm cli.js found (npm not installed via nvm/global?)"
fi

for F in "${CLIS[@]}"; do
  size=$(wc -c < "$F" | tr -d ' ')
  flags=$(stat -f '%Sf' "$F" 2>/dev/null)
  hit=$(grep -c -F "$SIG" "$F" 2>/dev/null); hit=${hit:-0}
  echo "cli.js: $F"
  echo "  size=$size bytes  flags=${flags:-none}"
  if [[ "$hit" -gt 0 || "$size" -gt 1000 ]]; then
    red "  >> TROJANIZED (payload marker / abnormal size)"
    INFECTED=1
    if [[ "$KILL" -eq 1 ]]; then
      chflags nouchg "$F" 2>/dev/null
      cp "$F" "$F.INFECTED_$(date +%s)" 2>/dev/null   # keep evidence
      # restore the legit npm 10.x shim
      cat > "$F" <<'CLEAN'
const validateEngines = require('./cli/validate-engines.js')
const cliEntry = require('node:path').resolve(__dirname, 'cli/entry.js')

module.exports = (process) => validateEngines(process, () => require(cliEntry))
CLEAN
      chflags uchg "$F" 2>/dev/null
      grn "  >> healed + locked immutable (uchg)"
    fi
  else
    grn "  >> clean"
    if [[ "$flags" != *uchg* && "$KILL" -eq 1 ]]; then
      chflags uchg "$F" 2>/dev/null && grn "  >> locked immutable (uchg)"
    fi
  fi
done
hr

# ----------------------------------------------------------------------
# 3. Hardening status
# ----------------------------------------------------------------------
isc=$(npm config get ignore-scripts 2>/dev/null)
echo "npm ignore-scripts: ${isc:-unknown}   (want: true)"
if [[ "$isc" != "true" && "$KILL" -eq 1 ]]; then
  npm config set ignore-scripts true 2>/dev/null && grn ">> set ignore-scripts=true"
fi
# ~/.node_modules: a DIRECTORY = real worm lair (bad). An immutable empty FILE
# = our blocker that prevents the worm from installing worker deps (good).
lair="$HOME/.node_modules"
if [[ -d "$lair" ]]; then
  ylw ">> worm lair present (directory): $lair"
  INFECTED=1
  if [[ "$KILL" -eq 1 ]]; then
    chflags -R nouchg "$lair" 2>/dev/null; rm -rf "$lair"
    touch "$lair" && chflags uchg "$lair" && grn ">> lair removed + blocked (immutable file)"
  fi
elif [[ -f "$lair" ]]; then
  echo "worm lair: blocked (immutable file present, good)"
  [[ "$KILL" -eq 1 ]] && chflags uchg "$lair" 2>/dev/null
else
  echo "worm lair (~/.node_modules): absent"
  [[ "$KILL" -eq 1 ]] && touch "$lair" && chflags uchg "$lair" && grn ">> installed lair blocker (immutable file)"
fi
hr

# ----------------------------------------------------------------------
# 4. Kill phase
# ----------------------------------------------------------------------
if [[ "$KILL" -eq 1 && ( "$workers" -gt 0 || "$npmw" -gt 0 ) ]]; then
  bold "killing worm processes..."
  for pid in $(list_workers) $(list_npmw); do kill -9 "$pid" 2>/dev/null; done
  sleep 2
  left=$(list_workers | wc -l | tr -d ' ')
  echo "workers after kill: $left"
  [[ "$left" -eq 0 ]] && grn ">> all workers terminated"
  hr
fi

# ----------------------------------------------------------------------
# Verdict
# ----------------------------------------------------------------------
if [[ "$INFECTED" -eq 1 ]]; then
  if [[ "$KILL" -eq 1 ]]; then
    ylw "VERDICT: infection found + remediated. Re-run to confirm clean."
    ylw "Reminder: rotate credentials (npm token, SSH keys, .env, cloud)."
  else
    red "VERDICT: INFECTED. Re-run with --kill to remediate:"
    red "    $0 --kill"
  fi
  exit 1
else
  grn "VERDICT: clean. No worm activity or trojanized npm detected."
  exit 0
fi
