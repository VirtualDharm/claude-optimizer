// ccstatusline custom-command widget (Windows/Bun): session title.
// Prints the /title custom title when one is set, else the first 8 chars of the
// session id. Scans only the transcript tail so big transcripts stay fast.
import { openSync, readSync, closeSync, statSync, readFileSync } from 'fs';
import { basename } from 'path';

const TAIL_BYTES = 524288;

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

function name(): string {
    let data: { transcript_path?: string; session_id?: string };
    try {
        data = JSON.parse(readFileSync(0, 'utf8'));
    } catch { return '?'; }

    const transcript = data.transcript_path;
    if (transcript) {
        try {
            const matches = [...tail(transcript).matchAll(/"customTitle":"([^"]+)"/g)];
            const last = matches[matches.length - 1];
            if (last) return last[1]!;
        } catch { /* fall through to session id */ }
    }

    const sid = data.session_id ?? (transcript ? basename(transcript, '.jsonl') : '');
    return sid ? sid.slice(0, 8) : '?';
}

process.stdout.write(name());
