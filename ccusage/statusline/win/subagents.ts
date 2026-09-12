// ccstatusline custom-command widget (Windows/Bun): running subagent count.
// Reads the statusline JSON payload on stdin, tails the transcript, and counts
// Task/Agent tool_use ids that have no matching tool_result yet. Prints "0" when none.
import { openSync, readSync, closeSync, statSync } from 'fs';

const TAIL_BYTES = 262144;

function readTail(path: string): string {
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

function count(): number {
    let raw = '';
    try {
        raw = require('fs').readFileSync(0, 'utf8');
    } catch { return 0; }

    let transcript: string | undefined;
    try {
        transcript = JSON.parse(raw)?.transcript_path;
    } catch { return 0; }
    if (!transcript) return 0;

    let buf = '';
    try {
        buf = readTail(transcript);
    } catch { return 0; }

    const started = new Set<string>();
    for (const m of buf.matchAll(/"type":"tool_use","id":"(toolu_[A-Za-z0-9]+)","name":"(?:Task|Agent)"/g))
        started.add(m[1]!);
    if (started.size === 0) return 0;

    for (const m of buf.matchAll(/"tool_use_id":"(toolu_[A-Za-z0-9]+)"/g))
        started.delete(m[1]!);

    return started.size;
}

process.stdout.write(String(count()));
