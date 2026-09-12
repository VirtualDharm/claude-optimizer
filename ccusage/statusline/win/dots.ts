// ccstatusline custom-command widget (Windows/Bun): account letters + status dots.
// Output: "<acct> ● ●" with raw ANSI, so set preserveColors: true on the widget.
//   acct  = first two chars of the active Claude account email (bright cyan)
//   dot 1 = caveman: green active / red inactive
//   dot 2 = rtk:     yellow active / purple inactive
import { existsSync, readFileSync } from 'fs';
import { homedir, tmpdir } from 'os';
import { join } from 'path';

const RESET = '\u001b[0m';
const paint = (code: string, text: string) => `\u001b[${code}m${text}${RESET}`;

function settings(): { enabledPlugins?: Record<string, boolean>; hooks?: unknown } {
    try {
        return JSON.parse(readFileSync(join(homedir(), '.claude', 'settings.json'), 'utf8').replace(/^﻿/, ''));
    } catch { return {}; }
}

function sessionId(): string {
    try {
        const data = JSON.parse(readFileSync(0, 'utf8'));
        if (data.session_id) return data.session_id;
        if (data.transcript_path) return String(data.transcript_path).replace(/^.*[\/]/, '').replace(/\.jsonl$/, '');
    } catch { /* no payload */ }
    return '';
}

const cfg = settings();

// caveman: per-session marker file wins; otherwise fall back to the plugin being enabled.
const sid = sessionId();
const marker = sid ? join(tmpdir(), `.cc_cave_s.${sid}`) : '';
let caveman: boolean;
if (marker && existsSync(marker))
    caveman = readFileSync(marker, 'utf8').trim() === '1';
else
    caveman = Object.entries(cfg.enabledPlugins ?? {}).some(([k, v]) => k.startsWith('caveman@') && v);

// rtk: binary reachable and the rewrite hook registered.
const rtkOnPath = [
    join(homedir(), 'AppData', 'Local', 'Microsoft', 'WinGet', 'Links', 'rtk.exe'),
    join(homedir(), '.cargo', 'bin', 'rtk.exe')
].some(p => existsSync(p));
const rtk = rtkOnPath && JSON.stringify(cfg.hooks ?? {}).includes('rtk hook claude');

// account letters
let acct = '??';
for (const file of [join(process.env.CLAUDE_CONFIG_DIR ?? homedir(), '.claude.json'), join(homedir(), '.claude.json')]) {
    try {
        const email = JSON.parse(readFileSync(file, 'utf8'))?.oauthAccount?.emailAddress;
        if (typeof email === 'string' && email.length > 0) { acct = email.slice(0, 2).toLowerCase(); break; }
    } catch { /* try next candidate */ }
}

process.stdout.write([
    paint('1;36', acct),
    paint(caveman ? '32' : '31', '\u25cf'),
    paint(rtk ? '33' : '35', '\u25cf')
].join(' '));
