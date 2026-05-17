#!/bin/bash
# Stop hook: nudge /compact only when context is high enough to matter.
# Tiered, not threshold-bark: silent below ~60%, scales tone above.

input=$(cat)

printf '%s' "$input" | python3 -c "
import sys, json, os

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tp = d.get('transcript_path')
if not tp or not os.path.exists(tp):
    sys.exit(0)

# Detect window: settings.autoCompactWindow > 1m model heuristic > 200k default.
window = 200000
try:
    with open(os.path.expanduser('~/.claude/settings.json')) as f:
        cfg = json.load(f)
        if isinstance(cfg.get('autoCompactWindow'), int):
            window = cfg['autoCompactWindow']
except Exception:
    pass

# Tail last ~2MB and find newest assistant message with usage.
total = None
model = ''
try:
    with open(tp, 'rb') as f:
        f.seek(0, 2)
        size = f.tell()
        read = min(size, 2 * 1024 * 1024)
        f.seek(size - read)
        tail = f.read().decode('utf-8', errors='replace').splitlines()
    for line in reversed(tail):
        if not line.strip():
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        msg = ev.get('message') or {}
        usage = msg.get('usage')
        if not usage:
            continue
        total = (
            int(usage.get('input_tokens') or 0)
            + int(usage.get('cache_read_input_tokens') or 0)
            + int(usage.get('cache_creation_input_tokens') or 0)
        )
        model = msg.get('model') or ''
        break
except Exception:
    sys.exit(0)

if total is None:
    sys.exit(0)

# 1M-window models: opus-4-7 with [1m], sonnet 4-6/4-7 with [1m].
if '[1m]' in model or '1m' in model.lower():
    window = max(window, 1000000)

pct = (total / window) * 100 if window else 0
tokens_k = total / 1000

# Tiered nudge: silent below 60%.
if pct < 60:
    sys.exit(0)
elif pct < 75:
    msg = f'Context at {pct:.0f}% ({tokens_k:.0f}k / {window//1000}k). Fine to keep going; /compact at next natural stopping point.'
elif pct < 85:
    msg = f'Context at {pct:.0f}% ({tokens_k:.0f}k / {window//1000}k). Recommend /compact before starting anything big.'
elif pct < 95:
    msg = f'Context at {pct:.0f}% ({tokens_k:.0f}k / {window//1000}k). Strongly recommend /compact now; auto-compact soon.'
else:
    msg = f'Context at {pct:.0f}% ({tokens_k:.0f}k / {window//1000}k). /compact NOW or risk auto-compact mid-task.'

print(json.dumps({'systemMessage': msg}))
" 2>/dev/null

exit 0
