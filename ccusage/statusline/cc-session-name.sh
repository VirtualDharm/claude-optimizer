#!/usr/bin/env bash
# ccstatusline custom-command widget: shows the session's custom title (e.g.
# "cs1-wondrfly-run&fixes") if one was set via /title, else a short session-id
# fallback. Meant to sit at the END of the line so the session is identifiable
# without moving the cursor back through the whole statusline.
set -uo pipefail
input="$(cat)"
g() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

TP="$(g '.transcript_path')"
SID="$(g '.session_id')"
[ -z "$SID" ] || [ "$SID" = "null" ] || SID="$SID"
if { [ -z "$SID" ] || [ "$SID" = "null" ]; } && [ -n "$TP" ] && [ "$TP" != "null" ]; then
  SID="$(basename "$TP" .jsonl)"
fi

TITLE=""
if [ -n "$TP" ] && [ "$TP" != "null" ] && [ -f "$TP" ]; then
  # -m1: stop at first match. Transcripts are huge (many MB); title rarely
  # changes mid-session, so scanning the whole file for the *last* match
  # (previously `tail -1`) blew the 400ms ccstatusline timeout.
  TITLE="$(grep -m1 -o '"customTitle":"[^"]*"' "$TP" 2>/dev/null | sed 's/^"customTitle":"//;s/"$//')"
fi

if [ -n "$TITLE" ]; then
  printf '%s' "$TITLE"
elif [ -n "$SID" ] && [ "$SID" != "null" ]; then
  printf '%s' "${SID:0:8}"
else
  printf '?'
fi
exit 0
