# cc-tools — Claude Code session helpers

Small CLIs for a multi-account Claude Code setup where every profile shares one hub
(`~/.claude-wondrfly`, see `cc-setup.sh`). Install = symlink into PATH:

```bash
ln -s "$PWD"/{ccwho,ccsessions} ~/.local/bin/
ln -s "$PWD"/ram ~/bin/
ln -s "$PWD"/{ccls,ccdel,ccprompts,ccsearch,cclib.py,cc-export} ~/.claude-wondrfly/bin/
```

| Tool | Does |
|---|---|
| `ccwho` | which claude.ai account each profile dir (`claude`, `claude1..3`) is logged into; flags mismatches |
| `ccls [proj]` | list sessions: title, id, date, size, project |
| `ccprompts <name\|id>` | print the user prompts of a session |
| `ccsearch <regex>` | grep across all session transcripts |
| `ccdel <name\|id>` | delete a session transcript |
| `ccsessions ls\|rm\|prune` | older bash session manager (age/size/prune) |
| `cc-export [--with-sessions]` | pack hub config + tools into `~/Desktop/cc-migrate-<date>.tar.gz` for another Mac |
| `ram` | macOS task manager: memory/disk dashboard, `ram ports`, `ram port <n>` to free one, `ram clean`, `ram big` |
| `cc-setup.sh` | restore on a new Mac (tools, hub, profile symlinks, zshrc, plugins, Brave native host) |

`cclib.py` = shared helpers (session listing/resolution). Python 3 required; `jq` only for
`ccsessions`. Project slugs (`-Users-<user>-...`) derive from `$HOME`, no hardcoded user.

## Windows

`ccwho`, `ccls`, `ccprompts`, `ccsearch` and `ccdel` are pure Python 3 and run as-is.
`ccdel` was rewritten from zsh for this. The session store is resolved by `cclib._root()`:
`CLAUDE_CONFIG_DIR` if set, else the hub, else `~/.claude` — so no hub is needed.

Install = one `.cmd` shim per tool in a directory already on `PATH`:

```bat
@echo off
"%LOCALAPPDATA%\Programs\Python\Python313\python.exe" "<repo>\cc-tools\ccls" %*
```

`ram` is ported separately as `ram.ps1` (PowerShell 5.1). Same commands as the zsh version
plus `ram gpu`: it labels every process `iGPU` or `dGPU`, so you can see which apps actually
landed on the discrete card. The discrete adapter is identified by dedicated VRAM, since
integrated graphics report none. `COMMIT` replaces `SWAP` — Windows has no swap file to
measure, and commit charge is the equivalent pressure signal.

Keep `ram.ps1` saved as **UTF-8 with BOM**. It draws bars and arrows with non-ASCII
characters, and PowerShell 5.1 misreads a BOM-less file, which breaks string parsing in
places far from the actual character.

Not ported: `ccsessions` (needs `jq`), `cc-export` and `cc-setup.sh` (Mac migration:
Homebrew, zshrc, Keychain, Brave native host).
