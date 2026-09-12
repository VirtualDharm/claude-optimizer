#!/usr/bin/env bash
# cc-setup.sh — restore Claude Code multi-account setup on a new Mac.
# Run from inside the extracted cc-migrate/ folder:  ./cc-setup.sh
# Idempotent. Never touches accounts/credentials — you log in per profile at the end.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
HUB="$HOME/.claude-wondrfly"
OLDHOME="/Users/mac"
say(){ printf '\n▶ %s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ── 0. tools ───────────────────────────────────────────────────────────────
say "tools"
have claude || curl -fsSL https://claude.ai/install.sh | bash
have bun    || curl -fsSL https://bun.sh/install | bash
have uv     || curl -LsSf https://astral.sh/uv/install.sh | sh
have jq     || { mkdir -p "$HOME/.local/bin"; curl -fsSL -o "$HOME/.local/bin/jq" https://github.com/jqlang/jq/releases/latest/download/jq-macos-amd64; chmod +x "$HOME/.local/bin/jq"; }
have rtk    || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/main/install.sh | sh
if [ ! -d "$HOME/.nvm" ]; then curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash; fi
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" 2>/dev/null || true
have node || { nvm install 20; nvm alias default 20; }
have pnpm || npm i -g pnpm
have gh   || echo "  (gh not installed — get from https://github.com/cli/cli/releases, put in ~/bin)"
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/bin:$PATH"

# ── 1. hub ─────────────────────────────────────────────────────────────────
say "hub → $HUB"
mkdir -p "$HUB" "$HUB/projects" "$HUB/sessions" "$HUB/plugins"
cp -R "$SRC/hub/." "$HUB/"
# rewrite hard-coded old home paths
grep -rl "$OLDHOME" "$HUB/settings.json" "$HUB/settings.local.json" "$HUB/hooks" "$HUB/bin" "$HUB/statusline-command.sh" "$HUB/CLAUDE.md" 2>/dev/null \
  | xargs -I{} sed -i '' "s#$OLDHOME#$HOME#g" {} || true
chmod +x "$HUB"/hooks/*.sh "$HUB"/bin/cc* 2>/dev/null || true

# ── 2. shared skills source + helper CLIs + statusline cfg ─────────────────
say "skills / bins / statusline config"
mkdir -p "$HOME/.agents" "$HOME/.local/bin" "$HOME/.config"
[ -d "$SRC/agents-skills" ] && { rm -rf "$HOME/.agents/skills"; cp -R "$SRC/agents-skills" "$HOME/.agents/skills"; }
# re-point hub skills at ~/.agents/skills (real dirs stay real)
for s in "$HOME/.agents/skills"/*/; do n="$(basename "$s")"; s="${s%/}"
  [ -e "$HUB/skills/$n" ] && [ ! -L "$HUB/skills/$n" ] && rm -rf "$HUB/skills/$n"
  ln -sfn "$s" "$HUB/skills/$n"; done
cp "$SRC/local-bin/"* "$HOME/.local/bin/"; chmod +x "$HOME/.local/bin/ccwho" "$HOME/.local/bin/ccsessions"
[ -d "$SRC/config/ccstatusline" ] && { rm -rf "$HOME/.config/ccstatusline"; cp -R "$SRC/config/ccstatusline" "$HOME/.config/"; sed -i '' "s#$OLDHOME#$HOME#g" "$HOME/.config/ccstatusline/settings.json"; }

# ── 3. claude-optimizer (hooks, statusline, virus-killer) ──────────────────
say "claude-optimizer"
OPT="$HOME/Projects2/claude-optimizer"; mkdir -p "$HOME/Projects2"
if [ ! -d "$OPT" ]; then
  git clone git@github.com:VirtualDharm/claude-optimizer.git "$OPT" 2>/dev/null || { mkdir -p "$OPT"; echo "  (clone failed — using bundled copy)"; }
fi
cp -R "$SRC/claude-optimizer/." "$OPT/"
chmod +x "$OPT"/hooks/*.sh "$OPT"/virus-killer/*.sh "$OPT"/ccusage/statusline/*.sh "$OPT"/cc-tools/* 2>/dev/null || true
# cc-tools: repo is source of truth → replace tarball copies with symlinks
if [ -d "$OPT/cc-tools" ]; then
  for t in ccwho ccsessions; do ln -sfn "$OPT/cc-tools/$t" "$HOME/.local/bin/$t"; done
  for t in ccls ccdel ccprompts ccsearch cclib.py cc-export; do ln -sfn "$OPT/cc-tools/$t" "$HUB/bin/$t"; done
  echo "  cc-tools symlinked from repo"
fi

# ── 4. profile dirs + symlinks into hub ────────────────────────────────────
say "profiles"
LINKS="CLAUDE.md RTK.md agents agents-removed-china cache chrome context-mode downloads file-history history.jsonl hooks image-cache jobs paste-cache plans plugins projects session-env shell-snapshots skills statusline-command.sh settings.json settings.local.json tasks"
for d in cache chrome context-mode downloads file-history image-cache jobs paste-cache plans session-env shell-snapshots tasks; do mkdir -p "$HUB/$d"; done
touch "$HUB/history.jsonl"
for P in .claude .claude-personal .claude-cs1; do
  D="$HOME/$P"; mkdir -p "$D/sessions"
  for L in $LINKS; do [ -e "$HUB/$L" ] || continue
    if [ -e "$D/$L" ] && [ ! -L "$D/$L" ]; then mv "$D/$L" "$D/$L.pre-migrate"; fi
    ln -sfn "$HUB/$L" "$D/$L"; done
done

# ── 5. shell ───────────────────────────────────────────────────────────────
say "zshrc"
if ! grep -q "Claude Code accounts" "$HOME/.zshrc" 2>/dev/null; then
  { echo; sed "s#$OLDHOME#$HOME#g" "$SRC/zshrc-claude.snippet"; } >> "$HOME/.zshrc"
  echo "  appended Claude block"; else echo "  Claude block already present"; fi
grep -q 'NVM_DIR' "$HOME/.zshrc" || printf '\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' >> "$HOME/.zshrc"
grep -q 'BUN_INSTALL' "$HOME/.zshrc" || printf '\nexport BUN_INSTALL="$HOME/.bun"\nexport PATH="$BUN_INSTALL/bin:$PATH"\n' >> "$HOME/.zshrc"
grep -q '.local/bin' "$HOME/.zshrc" || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"

# ── 6. plugins ─────────────────────────────────────────────────────────────
say "plugins (vercel, context-mode)"
export CLAUDE_CONFIG_DIR="$HUB"
claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null || true
claude plugin marketplace add mksglu/context-mode 2>/dev/null || true
claude plugin install vercel@claude-plugins-official 2>/dev/null || true
claude plugin install context-mode@context-mode 2>/dev/null || true

# ── 7. Brave + Claude extension native host ────────────────────────────────
say "browser"
NM="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
if [ -d "$(dirname "$NM")" ]; then
  mkdir -p "$NM" "$HUB/chrome"
  printf '#!/bin/sh\nexec %s/.local/bin/claude --chrome-native-host\n' "$HOME" > "$HUB/chrome/chrome-native-host"; chmod +x "$HUB/chrome/chrome-native-host"
  sed "s#$OLDHOME#$HOME#g" "$SRC/browser/com.anthropic.claude_code_browser_extension.json" > "$NM/com.anthropic.claude_code_browser_extension.json"
  echo "  native host registered for Brave"
else echo "  Brave not installed — install https://brave.com then re-run (native host step only)"; fi
echo "  extensions to install (Chrome Web Store):"; cut -f2,3 "$SRC/browser/brave-extensions.txt" | sed 's/^/    /'

# ── 8. done ────────────────────────────────────────────────────────────────
cat <<TXT

✔ setup done. Now LOG IN each account — one at a time, in a browser window that is
  NOT signed into any other claude.ai account (use separate Brave profiles or a
  private window; /login reuses whatever claude.ai session the browser already has):

    source ~/.zshrc
    claude1     # → /login → claude1@wondrfly.com
    claude2     # → /login → mdharm4air.fm@gmail.com
    claude3     # → /login → chatgptlogin9079@gmail.com
    claude      # → bare/general

  Verify:  ccwho
  Brave:   install "Claude" extension (id fcoeoabgfenejglbffodgkkbkcdhcgfn), then in a
           Claude Code session run  claude --chrome-setup  or  /chrome  to pair.
  Optional: git clone office repos to ~/Projects3; gh auth login.
TXT
