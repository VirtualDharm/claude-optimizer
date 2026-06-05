#!/usr/bin/env bash
# Subagents always-show wrapper. Output "0" when none running.
set -uo pipefail
input="$(cat)"
TP="$(printf '%s' "$input" | grep -oE '"transcript_path":"[^"]+"' | head -1 | sed 's/.*:"//;s/"$//')"
if [ -z "$TP" ] || [ ! -f "$TP" ]; then printf '0'; exit 0; fi
buf="$(tail -c 262144 "$TP" 2>/dev/null)"
[ -n "$buf" ] || { printf '0'; exit 0; }
u="$(printf '%s' "$buf" | grep -oE '"type":"tool_use","id":"toolu_[A-Za-z0-9]+","name":"(Task|Agent)"' | grep -oE 'toolu_[A-Za-z0-9]+' | sort -u)"
[ -n "$u" ] || { printf '0'; exit 0; }
r="$(printf '%s' "$buf" | grep -oE '"tool_use_id":"toolu_[A-Za-z0-9]+"' | grep -oE 'toolu_[A-Za-z0-9]+' | sort -u)"
n="$(comm -23 <(printf '%s\n' "$u") <(printf '%s\n' "$r") | grep -c .)"
printf '%d' "${n:-0}"
exit 0
