#!/usr/bin/env python3
"""
Bypass digest — aggregates all bypass_log.txt files across /tmp/cc-gates
sessions and produces a structured summary.

Output is consumed by the /bypass-audit slash command.

Log line format (set by pre-commit-gate.sh / visual-qa-stop-gate.sh / etc.):
  YYYY-MM-DD HH:MM:SS | <gate-name> | <USER APPROVED|...> | <reason>
"""
import collections
import datetime as dt
import re
from pathlib import Path
from typing import Iterable


GATE_DIR = Path("/tmp/cc-gates")
LINE_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*\|\s*"
    r"(?P<gate>[^|]+?)\s*\|\s*"
    r"(?P<status>[^|]*?)\s*\|\s*"
    r"(?P<reason>.*)$"
)


def iter_bypass_lines() -> Iterable[tuple[dt.datetime, str, str, str, str]]:
    if not GATE_DIR.exists():
        return
    for log in GATE_DIR.glob("*/bypass_log.txt"):
        session = log.parent.name
        try:
            for line in log.read_text(encoding="utf-8", errors="ignore").splitlines():
                m = LINE_RE.match(line.strip())
                if not m:
                    continue
                try:
                    ts = dt.datetime.strptime(m["ts"], "%Y-%m-%d %H:%M:%S")
                except ValueError:
                    continue
                yield ts, m["gate"].strip(), m["status"].strip(), m["reason"].strip(), session
        except OSError:
            continue


def cluster_reasons(reasons: list[str], top: int = 1) -> list[tuple[str, int]]:
    """Crude clustering: lowercase, strip punctuation, group by first 6 words."""
    norm = []
    for r in reasons:
        clean = re.sub(r"[^\w\s]", " ", r.lower())
        words = clean.split()[:6]
        norm.append(" ".join(words) or "(empty)")
    counts = collections.Counter(norm)
    return counts.most_common(top)


def main():
    rows = list(iter_bypass_lines())
    if not rows:
        print("No bypass log entries found in /tmp/cc-gates/.")
        return

    earliest = min(r[0] for r in rows)
    latest = max(r[0] for r in rows)
    days_span = (latest - earliest).days or 1

    by_gate: dict[str, list[tuple[dt.datetime, str, str, str]]] = collections.defaultdict(list)
    for ts, gate, status, reason, session in rows:
        by_gate[gate].append((ts, status, reason, session))

    sessions = {r[4] for r in rows}
    week_ago = dt.datetime.now() - dt.timedelta(days=7)
    recent = [r for r in rows if r[0] >= week_ago]
    recent_sessions = {r[4] for r in recent}

    print(f"Bypass Audit — {len(rows)} bypass(es) across {len(sessions)} session(s)")
    print(f"Range: {earliest.date()} to {latest.date()} ({days_span} days)")
    print()
    print(f"Recent activity (last 7 days): {len(recent)} bypass(es) across {len(recent_sessions)} session(s)")
    print()
    print("Most-bypassed gates:")
    print("-" * 60)

    sorted_gates = sorted(by_gate.items(), key=lambda kv: -len(kv[1]))
    for i, (gate, entries) in enumerate(sorted_gates[:10], 1):
        reasons = [r[2] for r in entries]
        clusters = cluster_reasons(reasons, top=2)
        cluster_str = "; ".join(f'"{c}" (×{n})' for c, n in clusters)
        recent_count = sum(1 for r in entries if r[0] >= week_ago)
        print(f"{i}. {gate:30} {len(entries):4} total  {recent_count:3} this week")
        print(f"     top cluster(s): {cluster_str}")
        # Also list distinct unclusterable reasons
        unique_reasons = sorted({r for r in reasons if r and len(r) > 20})
        if unique_reasons:
            for r in unique_reasons[:3]:
                print(f'     · "{r[:100]}"')
        print()

    # Suspicious: bypasses without explicit reason
    no_reason = sum(1 for r in rows if not r[3] or r[3] == "(user-approved)")
    if no_reason:
        print(f"⚠ {no_reason} bypass(es) had no Claude-supplied reason "
              "(user approved without rationale).")
        print()


if __name__ == "__main__":
    main()
