#!/usr/bin/env bash
# Project name: git repo root basename (so a subfolder like ccusage/ still shows
# "claude-optimizer"). Falls back to the cwd basename outside a git repo.
set -uo pipefail
input="$(cat)"
CWD="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)"
[ -n "$CWD" ] || exit 0
ROOT=""
if command -v git >/dev/null 2>&1; then
  ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
fi
printf '%s' "$(basename "${ROOT:-$CWD}")"
exit 0
