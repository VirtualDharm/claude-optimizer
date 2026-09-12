import os, glob, json, datetime

SLUG = '-' + os.path.expanduser('~').strip('/').replace('/', '-') + '-'   # e.g. '-Users-mac-'

def _root():
    """Session store: CLAUDE_CONFIG_DIR wins, else the hub, else plain ~/.claude.
    Windows has no hub, so it falls through to ~/.claude/projects."""
    env = os.environ.get('CLAUDE_CONFIG_DIR')
    if env:
        return os.path.join(env, 'projects')
    for d in ('~/.claude-wondrfly/projects', '~/.claude/projects'):
        p = os.path.expanduser(d)
        if os.path.isdir(p):
            return p
    return os.path.expanduser('~/.claude/projects')


ROOT = _root()

def sessions(proj_filter=None):
    """Yield dicts: sid, file, proj, mtime, size, title."""
    for f in glob.glob(os.path.join(ROOT, '*', '*.jsonl')):
        proj = os.path.basename(os.path.dirname(f)).replace(SLUG, '~/')
        if proj_filter and proj_filter.lower() not in proj.lower(): continue
        sid = os.path.basename(f)[:-6]
        title = ''
        try:
            with open(f, encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    if '"custom-title"' in line:
                        try: title = json.loads(line).get('customTitle', '') or title
                        except Exception: pass
        except OSError: continue
        yield {'sid': sid, 'file': f, 'proj': proj, 'title': title,
               'mtime': os.path.getmtime(f), 'size': os.path.getsize(f)}

def resolve(query, proj_filter=None):
    """Match query against session id prefix or title substring. Return list."""
    q = query.lower()
    out = []
    for s in sessions(proj_filter):
        if s['sid'].startswith(q) or q in s['title'].lower():
            out.append(s)
    return out

def fmt_size(n):
    for u in ['B','K','M','G']:
        if n < 1024 or u == 'G': return f"{n:.0f}{u}" if u=='B' else f"{n:.1f}{u}"
        n /= 1024

def fmt_date(t):
    return datetime.datetime.fromtimestamp(t).strftime('%Y-%m-%d')

def user_prompts(f):
    """Yield (timestamp, text) for real user prompts in a transcript."""
    with open(f, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            if '"type":"user"' not in line: continue
            try: d = json.loads(line)
            except Exception: continue
            if d.get('type') != 'user': continue
            m = d.get('message', {})
            c = m.get('content', '')
            if isinstance(c, list):
                c = ' '.join(x.get('text','') for x in c if isinstance(x,dict) and x.get('type')=='text')
            if not isinstance(c, str) or not c.strip(): continue
            t = c.strip()
            # skip tool results / injected system content
            if t.startswith(('<system-reminder', '[{', '<command-', '<task-notification', 'Caveman mode', '<local-command', '<command-message')): continue
            if d.get('isMeta') or d.get('toolUseResult'): continue
            yield d.get('timestamp',''), t
