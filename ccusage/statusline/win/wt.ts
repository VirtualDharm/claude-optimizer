// ccstatusline custom-command widget (Windows/Bun): active worktree name.
// Prints the worktree name, or an em-dash when the cwd is a normal checkout.
import { execFileSync } from 'child_process';
import { readFileSync } from 'fs';
import { basename } from 'path';

const NONE = '\u2014';

function worktree(): string {
    let cwd: string | undefined;
    try {
        cwd = JSON.parse(readFileSync(0, 'utf8'))?.workspace?.current_dir;
    } catch { return NONE; }
    if (!cwd) return NONE;

    const git = (...args: string[]) =>
        execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();

    try {
        if (!git('rev-parse', '--absolute-git-dir').includes('/worktrees/')) return NONE;
        return basename(git('rev-parse', '--show-toplevel'));
    } catch { return NONE; }
}

process.stdout.write(worktree());
