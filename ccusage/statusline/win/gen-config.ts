// Regenerates ~/.config/ccstatusline/settings.json for this machine.
// Run: bun statusline/win/gen-config.ts
import { mkdirSync, writeFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

const BUN = 'C:/Users/chatg/.bun/bin/bun.exe';
const WIN = 'D:/Apps/claude-optimizer/ccusage/statusline/win';
const cmd = (script: string) => `"${BUN}" "${WIN}/${script}"`;

let n = 0;
const id = () => String(++n);
const sep = () => ({ id: id(), type: 'separator' });

const settings = {
    version: 3,
    lines: [
        [
            // One process for account letters, both dots and the subagent count:
            // every extra custom-command widget costs a whole Bun spawn.
            { id: id(), type: 'custom-command', commandPath: cmd('left.ts'), timeout: 3000, preserveColors: true },
            sep(),
            { id: id(), type: 'git-root-dir', color: 'blue', rawValue: true },
            sep(),
            { id: id(), type: 'worktree-name', color: 'green' },
            sep(),
            { id: id(), type: 'git-branch', color: 'magenta' },
            sep(),
            { id: id(), type: 'model', color: 'cyan', rawValue: true },
            sep(),
            { id: id(), type: 'context-percentage', color: 'green', rawValue: true },
            sep(),
            { id: id(), type: 'reset-timer', color: 'yellow' },
            sep(),
            { id: id(), type: 'session-usage', color: 'yellow' },
            sep(),
            { id: id(), type: 'weekly-usage', color: 'brightMagenta' },
            sep(),
            { id: id(), type: 'session-clock', color: 'brightBlack', rawValue: true },
            sep(),
            { id: id(), type: 'session-name', color: 'brightGreen', rawValue: true }
        ],
        [],
        []
    ],
    flexMode: 'full-minus-40',
    compactThreshold: 60,
    colorLevel: 2,
    inheritSeparatorColors: false,
    globalBold: false,
    gitCacheTtlSeconds: 5,
    minimalistMode: false,
    powerline: {
        enabled: false,
        separators: [''],
        separatorInvertBackground: [false],
        startCaps: [],
        endCaps: [],
        autoAlign: false,
        continueThemeAcrossLines: false
    }
};

const dir = join(homedir(), '.config', 'ccstatusline');
mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, 'settings.json'), JSON.stringify(settings, null, 2), 'utf8');
console.log(`wrote ${join(dir, 'settings.json')} (${settings.lines[0]!.length} items)`);
