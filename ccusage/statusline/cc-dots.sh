#!/usr/bin/env bash
# ccstatusline custom-command widget: caveman + rtk status dots.
# Reads statusline JSON on stdin. Output: "● ●" with raw ANSI (set preserveColors:true).
#   dot 1 = caveman: green active / red inactive  (marker /tmp/.cc_cave_s.<session>)
#   dot 2 = rtk:     yellow active / purple inactive (binary on PATH + hook in settings.json)
set -uo pipefail
input="$(cat)"
g() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

SID="$(g '.session_id')"; { [ -z "$SID" ] || [ "$SID" = "null" ]; } && SID="$(basename "$(g '.transcript_path')" .jsonl)"
CAVE=0
[ -n "$SID" ] && [ "$SID" != "null" ] && [ "$(cat "/tmp/.cc_cave_s.$SID" 2>/dev/null)" = "1" ] && CAVE=1

RTK=0
if command -v rtk >/dev/null 2>&1 && \
   grep -q 'rtk hook claude' "$HOME/.claude/settings.json" 2>/dev/null; then RTK=1; fi

R=$'\033[0m'
[ "$CAVE" = "1" ] && c=$'\033[32m●'"$R" || c=$'\033[31m●'"$R"
[ "$RTK"  = "1" ] && r=$'\033[33m●'"$R" || r=$'\033[35m●'"$R"
printf '%s %s' "$c" "$r"
exit 0
