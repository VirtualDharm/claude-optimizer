# cc-tools — Claude Code session helpers

Small CLIs for a multi-account Claude Code setup where every profile shares one hub
(`~/.claude-wondrfly`, see `cc-setup.sh`). Install = symlink into PATH:

```bash
ln -s "$PWD"/{ccwho,ccsessions} ~/.local/bin/
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
| `cc-setup.sh` | restore on a new Mac (tools, hub, profile symlinks, zshrc, plugins, Brave native host) |

`cclib.py` = shared helpers (session listing/resolution). Python 3 + `jq` required.
Project slugs (`-Users-<user>-...`) derive from `$HOME`, no hardcoded user.
