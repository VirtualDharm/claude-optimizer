// ccstatusline custom-command widget (Windows/Bun): account letters, status dots,
// and the running subagent count in ONE process. Merged from dots.ts + subagents.ts
// because each extra widget costs a whole Bun spawn, and this machine has 4 GB of RAM.
// Output carries raw ANSI, so set preserveColors: true on the widget.
import { existsSync, openSync, readSync, closeSync, statSync, readFileSync } from 'fs';
import { homedir, tmpdir } from 'os';
import { join } from 'path';

const RESET = '\u001b[0m';
const paint = (code: string, text: string) => `\u001b[${code}m${text}${RESET}`;
const TAIL_BYTES = 262144;

let payload: { session_id?: string; transcript_path?: string } = {};
try {
    payload = JSON.parse(readFileSync(0, 'utf8'));
} catch { /* no payload: preview or manual run */ }

function json(path: string): Record<string, unknown> {
    try {
        return JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
    } catch { return {}; }
}

function tail(path: string): string {
    const size = statSync(path).size;
    const start = Math.max(0, size - TAIL_BYTES);
    const length = size - start;
    const buf = Buffer.alloc(length);
    const fd = openSync(path, 'r');
    try {
        readSync(fd, buf, 0, length, start);
    } finally {
        closeSync(fd);
    }
    return buf.toString('utf8');
}

const cfg = json(join(homedir(), '.claude', 'settings.json'));

// ── account letters ─────────────────────────────────────────────────────────
let acct = '??';
for (const file of [join(process.env.CLAUDE_CONFIG_DIR ?? homedir(), '.claude.json'), join(homedir(), '.claude.json')]) {
    const email = (json(file).oauthAccount as { emailAddress?: string } | undefined)?.emailAddress;
    if (email) { acct = email.slice(0, 2).toLowerCase(); break; }
}

// ── caveman dot: per-session marker wins, else the plugin being enabled ──────
const sid = payload.session_id
    ?? (payload.transcript_path ? payload.transcript_path.replace(/^.*[\/]/, '').replace(/\.jsonl$/, '') : '');
const marker = sid ? join(tmpdir(), `.cc_cave_s.${sid}`) : '';
const plugins = (cfg.enabledPlugins ?? {}) as Record<string, boolean>;
const caveman = marker && existsSync(marker)
    ? readFileSync(marker, 'utf8').trim() === '1'
    : Object.entries(plugins).some(([k, v]) => k.startsWith('caveman@') && v);

// ── rtk dot: binary present and the rewrite hook registered ─────────────────
const rtkOnPath = [
    join(homedir(), 'AppData', 'Local', 'Microsoft', 'WinGet', 'Links', 'rtk.exe'),
    join(homedir(), '.cargo', 'bin', 'rtk.exe')
].some(p => existsSync(p));
const rtk = rtkOnPath && JSON.stringify(cfg.hooks ?? {}).includes('rtk hook claude');

// ── subagents: Task/Agent tool_use ids with no tool_result yet ───────────────
let agents = 0;
if (payload.transcript_path) {
    try {
        const buf = tail(payload.transcript_path);
        const open = new Set<string>();
        for (const m of buf.matchAll(/"type":"tool_use","id":"(toolu_[A-Za-z0-9]+)","name":"(?:Task|Agent)"/g))
            open.add(m[1]!);
        for (const m of buf.matchAll(/"tool_use_id":"(toolu_[A-Za-z0-9]+)"/g))
            open.delete(m[1]!);
        agents = open.size;
    } catch { /* unreadable transcript */ }
}

process.stdout.write([
    paint('1;36', acct),
    paint(caveman ? '32' : '31', '\u25cf'),
    paint(rtk ? '33' : '35', '\u25cf'),
    paint(agents > 0 ? '33' : '90', String(agents))
].join(' '));
