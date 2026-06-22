# npm Supply-Chain Worm — Incident & Remediation

**Machine:** MacBook Air (Intel i5-5350U, 2017), macOS Monterey 12.7.6, 8 GB RAM
**Detected:** 2026-06-21 | **Status:** contained + hardened | **Open item:** credential rotation

---

## 1. Symptom
Laptop extremely slow. Measured:
- load average **373–451** (normal ~4 on 4-thread CPU)
- **~475 `node` processes**, 466 obfuscated `node -e` workers
- swap 3+ GB, CPU pinned/throttled

## 2. Root cause — trojanized npm
Worm appended an obfuscated VM-packed payload to npm's own entry file:
```
~/.nvm/versions/node/v20.20.2/lib/node_modules/npm/lib/cli.js
```
- Legit file = 4 lines / ~215 bytes. Infected = **72,453 bytes**.
- Payload hidden after legit code behind **1,057 spaces**, starts byte 416.
- Markers: `global['e']='NPM'`, `global.i='A8-**'`, build tags `/*C260512A*/ /*RS260605*/`.
- **Every `npm` invocation ran the payload** → spawned 100s of fileless `node -e` workers + `npm install --prefix ~/.node_modules socket.io-client/axios`, beaconing to cloud C2.

## 3. C2 (captured live via lsof)
Cloud-hosted, not personally attributable:
- AWS EC2 ap-southeast-1 (Singapore): `18.139.10.245`, `47.130.139.143`, `52.76.176.200`
- AWS Global Accelerator (C2 front): `52.223.34.155`, `35.71.137.105` → `a1d4ba62fdc34338f.awsglobalaccelerator.com`
- GCP: `35.186.203.48`
- No PTR: `23.27.13.43`
- (Cloudflare `104.16.x` = legit npm CDN, NOT C2)

## 4. Persistence / reinfection
- No LaunchAgent/cron/shell-rc/NODE_OPTIONS/npmrc/init-module/git-hook/ssh-backdoor.
- Persistence = **the patched npm itself**. Any `npm` call relit the whole worker loop.
- Dropper is a **fileless network loader** (fetches payload at runtime) — leaves nothing on disk. Signature search across entire home = **0 hits**, npm cache = 0.
- **Reinfected once:** clean-only fix at ~18:04 did NOT hold — npm re-patched **2026-06-21 20:46**, ran ~12h overnight → load 400 again next morning.
- **Reinfection vector:** an **AI IDE agent (Devin/Windsurf) auto-ran an install/npx** at 20:46 → loader fired → re-patched npm. Not a manual action.

## 5. Remediation applied (2026-06-22)
1. Killed all workers (`pkill -9 -f "node -e global"`, `pkill -9 -f "npm install"`).
2. Restored clean `cli.js` (215 bytes).
3. **Locked it immutable:** `chflags uchg <cli.js>` → worm cannot overwrite.
4. **Blocked install scripts:** `npm config set ignore-scripts true` (→ `~/.npmrc`).
5. Removed ephemeral lair `~/.node_modules`.
6. Nuked + reinstalled `~/Projects3/purple_investor_backend` node_modules clean (`npm ci`/`install --legacy-peer-deps --ignore-scripts`).
7. Deleted quarantine evidence file.
8. Staged pf firewall rules: `/Users/mac/malware-c2-block.conf` (NOT yet activated — needs sudo).

**Verified after:** load → ~2, workers 0, cli.js 215B + `uchg` + 0 payload, ignore-scripts true. Only node v20.20.2; bun 1.3.14 clean.

## 6. STILL OPEN — credential rotation (URGENT, ~12h+ exfil exposure)
Do from a **clean device**:
- [ ] npm token (revoke all, regen; check npmjs.com for rogue publishes)
- [ ] 3 GitHub SSH keys: `personal_ed25519`, `wondrfly_ed25519`, `zamboree_github`
- [ ] cloud keys (`~/.aws/credentials`) + all `.env` secrets (Stripe, OpenAI/ChatGPT, MongoDB)
- [ ] browser-saved passwords / sessions; reused passwords
Until done: treat every credential on this machine as compromised.

## 7. Firewall activation (run with sudo / `!` prefix)
```bash
sudo cp /Users/mac/malware-c2-block.conf /etc/pf.anchors/malware-c2
sudo pfctl -a malware-c2 -f /etc/pf.anchors/malware-c2 && sudo pfctl -e
```

---

## How to use the killer script
```bash
# detect only (safe, read-only)
/Users/mac/Projects2/claude-optimizer/virus-killer/check-npm-worm.sh

# detect + kill workers + heal/relock cli.js + set ignore-scripts
/Users/mac/Projects2/claude-optimizer/virus-killer/check-npm-worm.sh --kill
```
Run before AND after any AI-IDE agent session, or whenever the laptop feels slow.

## Detection cheatsheet (manual)
```bash
uptime                                   # load in hundreds = infected
pgrep -f "node -e global" | wc -l        # >0 = active worm
wc -c ~/.nvm/versions/node/*/lib/node_modules/npm/lib/cli.js   # >1000 = trojanized
grep -c "global\['e'\]" ~/.nvm/versions/node/*/lib/node_modules/npm/lib/cli.js
ls -lO ~/.nvm/.../npm/lib/cli.js         # want flag: uchg
```

## Safe-work rules
- **IDE:** VS Code, or Cursor/Windsurf with **agent auto-run OFF**. Never agent auto-execute installs (caused reinfection).
- **Projects:** before opening, `rm -rf node_modules && npm ci --ignore-scripts --legacy-peer-deps`.
- Avoid random `npx` / `npm i -g` of unfamiliar packages.
- Don't access sensitive accounts from this machine until credentials rotated.
