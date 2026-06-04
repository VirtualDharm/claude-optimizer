#!/usr/bin/env bash
# ccstatusline custom-command widget: count subagents currently running.
# Reads the statusline JSON on stdin (piped by ccstatusline's CustomCommand).
# A running subagent = a Task/Agent tool_use whose id has no matching
# tool_result.tool_use_id yet. While a subagent runs the main agent is blocked,
# so the tool_use sits at the tail of the transcript → tail is enough.
# Uses grep (byte-stream, fast) instead of jq: transcript tail lines can be
# multi-KB (big tool results) and jq slurp on them costs ~1s.
set -uo pipefail
input="$(cat)"
TP="$(printf '%s' "$input" | grep -oE '"transcript_path":"[^"]+"' | head -1 | sed 's/.*:"//;s/"$//')"
[ -n "$TP" ] && [ -f "$TP" ] || exit 0

# Bound by bytes, not lines: transcript lines can be tens of MB each, so
# `tail -n` would read enormous data. The running subagent's tool_use is in
# the last message → the last ~256KB is plenty (may clip one partial line).
buf="$(tail -c 262144 "$TP" 2>/dev/null)"
[ -n "$buf" ] || exit 0

# Task/Agent tool_use ids (block keys are emitted in type,id,name order)
u="$(printf '%s' "$buf" \
  | grep -oE '"type":"tool_use","id":"toolu_[A-Za-z0-9]+","name":"(Task|Agent)"' \
  | grep -oE 'toolu_[A-Za-z0-9]+' | sort -u)"
[ -n "$u" ] || exit 0
# all tool_result ids
r="$(printf '%s' "$buf" \
  | grep -oE '"tool_use_id":"toolu_[A-Za-z0-9]+"' \
  | grep -oE 'toolu_[A-Za-z0-9]+' | sort -u)"

n="$(comm -23 <(printf '%s\n' "$u") <(printf '%s\n' "$r") | grep -c .)"
[ "$n" -gt 0 ] 2>/dev/null && printf '🧑‍🚀 %s' "$n"
exit 0
