#!/usr/bin/env bash
# UserPromptSubmit (project-scoped, claude-optimizer): every 5th message (1,6,11,…)
# check whether the session's model drifted off Fable 5. Hooks CANNOT switch the live
# session model (settings.json "model" is read at startup only), so on drift we:
#   1) self-heal ~/.claude/settings.json "model" back to "fable" (fixes NEW sessions)
#   2) inject additionalContext so Claude opens its reply telling the user to run
#      /model fable (one keystroke fix for the CURRENT session).
set -uo pipefail
input="$(cat)"
g() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

SETTINGS="${FABLE_GUARD_SETTINGS:-$HOME/.claude/settings.json}"
WANT="fable"

SID="$(g '.session_id')"; { [ -z "$SID" ] || [ "$SID" = "null" ]; } && SID="$(basename "$(g '.transcript_path')" .jsonl)"
{ [ -z "$SID" ] || [ "$SID" = "null" ]; } && exit 0
TP="$(g '.transcript_path')"

NCACHE="/tmp/.cc_fable_n.$SID"
n=0; [ -f "$NCACHE" ] && n="$(cat "$NCACHE" 2>/dev/null)"; n=$((n + 1)); printf '%s' "$n" > "$NCACHE"
[ $(( n % 5 )) -eq 1 ] || exit 0

# last model the session actually replied with
MODEL=""
if [ -n "$TP" ] && [ -f "$TP" ]; then
  MODEL="$(jq -rs 'last(.[] | select(.message.model? and .message.model != null) | .message.model) // ""' "$TP" 2>/dev/null)"
fi
[ -n "$MODEL" ] || exit 0
case "$MODEL" in *fable*) exit 0 ;; esac   # already on Fable — nothing to do

# 1) heal the startup default so new sessions come up on Fable
if [ -f "$SETTINGS" ]; then
  CUR="$(jq -r '.model // ""' "$SETTINGS" 2>/dev/null)"
  if [ "$CUR" != "$WANT" ]; then
    TMP="$(mktemp)"
    if jq --arg m "$WANT" '.model = $m' "$SETTINGS" > "$TMP" 2>/dev/null && jq empty "$TMP" 2>/dev/null; then
      mv "$TMP" "$SETTINGS"
    else
      rm -f "$TMP"
    fi
  fi
fi

# 2) nudge the current session (hooks cannot switch a live session's model)
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"MODEL DRIFT: this session is running on %s, expected Fable 5. Begin your reply with one bold line telling the user to type /model fable to switch back. Default model in settings.json has been re-set to fable for new sessions. (Interval check, every 5th message.)"}}' "$MODEL"
exit 0
