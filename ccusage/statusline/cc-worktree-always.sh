#!/usr/bin/env bash
# Worktree always-show wrapper. Output "—" (em-dash) when not in a worktree.
set -uo pipefail
input="$(cat)"
CWD="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)"
[ -n "$CWD" ] || { printf '—'; exit 0; }
if command -v git >/dev/null 2>&1 && git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GITDIR="$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)"
  case "$GITDIR" in
    */worktrees/*) printf '%s' "$(basename "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)")"; exit 0 ;;
  esac
fi
printf '—'
exit 0
