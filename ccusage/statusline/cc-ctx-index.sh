#!/usr/bin/env bash
# ccstatusline custom-command widget: context-mode index health for this project.
# Reads statusline JSON on stdin. Output: "🗂 <chunks>·<last-index-age>·<tokens-saved>"
#   chunks       = total indexed chunks whose source path is under the current cwd
#   last-index   = age since the newest sources.indexed_at for this project
#   tokens-saved = lifetime tokens context-mode saved (from newest stats-pid json)
# Prints "🗂 none" when this project has nothing indexed yet.
set -uo pipefail
input="$(cat)"
CWD="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)"
[ -n "$CWD" ] || exit 0
# Resolve to git repo root so a subfolder (e.g. ccusage/) reports the whole project's
# index, not just files under the subfolder.
if command -v git >/dev/null 2>&1; then
  ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$ROOT" ] && CWD="$ROOT"
fi
CDIR="$HOME/.claude/context-mode/content"
[ -d "$CDIR" ] || exit 0

esc="${CWD//\'/\'\'}"                       # escape single quotes for SQL literal
best_ch=0; best_at=""
for db in "$CDIR"/*.db; do
  [ -f "$db" ] || continue
  row="$(sqlite3 -separator '|' "$db" \
    "SELECT COALESCE(SUM(chunk_count),0), COALESCE(MAX(indexed_at),'') FROM sources \
     WHERE file_path LIKE '${esc}%' OR label LIKE '%${esc}%';" 2>/dev/null)"
  ch="${row%%|*}"; at="${row#*|}"
  if [ "${ch:-0}" -gt "$best_ch" ] 2>/dev/null; then best_ch="$ch"; best_at="$at"; fi
done

if ! [ "$best_ch" -gt 0 ] 2>/dev/null; then printf '🗂 none'; exit 0; fi

# age since last index
age=""
if [ -n "$best_at" ]; then
  ts="$(date -j -f '%Y-%m-%d %H:%M:%S' "$best_at" +%s 2>/dev/null || date -d "$best_at" +%s 2>/dev/null)"
  if [ -n "$ts" ]; then
    d=$(( $(date +%s) - ts ))
    if   [ "$d" -lt 3600 ]; then age="$((d/60))m"
    elif [ "$d" -lt 86400 ]; then age="$((d/3600))h"
    else age="$((d/86400))d"; fi
  fi
fi

# lifetime tokens saved (newest per-pid stats file)
sv=""
sj="$(ls -t "$HOME/.claude/context-mode/sessions/stats-pid-"*.json 2>/dev/null | head -1)"
if [ -n "$sj" ]; then
  saved="$(jq -r '.tokens_saved_lifetime // 0' "$sj" 2>/dev/null)"
  [ -n "$saved" ] && [ "$saved" -gt 0 ] 2>/dev/null && sv="·$((saved/1000))k"
fi

printf '🗂 %s%s%s' "$best_ch" "${age:+·$age}" "$sv"
exit 0
