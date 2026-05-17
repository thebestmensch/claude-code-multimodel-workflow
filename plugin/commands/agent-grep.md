---
description: Symbol-aware ripgrep wrapper. Each hit shows the enclosing function or class so you don't need to follow up with a Read.
effort: low
---

Symbol-aware code search. Wraps ripgrep with enclosing-symbol context so each hit shows the function/class/method it lives inside, saving a Read call per hit.

> **What it does:** Runs `rg -n <pattern> [path]`, then for each hit walks backward in the file to find the nearest enclosing definition (Python `def`/`class`, JS/TS `function`/`const ... =`/`class`, Rust `fn`/`impl`/`struct`, Go `func`/`type`).

## Usage

```
/agent-grep <pattern> [path]
/agent-grep "useEffect" mobile-app/
/agent-grep "BaseModel" api/
/agent-grep "@shared_task"
```

If `[path]` is omitted, search the current working directory.

## Process

1. **Parse args** from `$ARGUMENTS`. First token is the pattern (quote-aware), rest is the optional path. If no args, prompt the user and stop.

2. **Run ripgrep** with line numbers and a reasonable cap:
   ```bash
   rg -n --max-count 50 --max-columns 200 "<pattern>" <path>
   ```
   If zero hits, report "no matches" and stop.

3. **For each hit `path:line:text`, find the enclosing symbol:**
   - Read lines `[1, line]` from the file
   - Walk backward from `line` to 1, return the first line matching one of these patterns (per file extension):
     - **Python (`.py`):** `^\s*(def|class|async def)\s+\w+`
     - **JS/TS (`.js`, `.ts`, `.tsx`, `.jsx`):** `^\s*(export\s+)?(async\s+)?(function|class|const|let|var)\s+\w+|^\s*\w+\s*[:=]\s*(async\s*)?\(`
     - **Rust (`.rs`):** `^\s*(pub\s+)?(async\s+)?(fn|impl|struct|enum|trait|mod)\s+\w+`
     - **Go (`.go`):** `^\s*(func|type)\s+\w+`
     - **Other:** skip the enclosing-symbol step
   - If found, capture the symbol declaration (first ~80 chars)
   - If not found within the file, mark as "(top-level)"

4. **Format output:**
   ```
   path/to/file.py:42: hit text here
     └─ in: def my_function(arg: str) -> None:
   path/to/other.tsx:128: another hit
     └─ in: export const MyComponent: FC<Props> = ({ ... }) =>
   ```

5. **Cap output** at 30 hits. If there are more, suggest narrowing the path or pattern.

## Implementation notes

- Use `head -n` and `tail -r` (or `awk`); reading the whole file is wasteful when only the first N lines up to the hit matter
- For very large files (>5MB), skip the symbol-context step for that hit and just print the bare ripgrep line (mark with `(symbol-context skipped: large file)`)
- Respect `.gitignore` (ripgrep does this by default; don't override)
- Don't try to parse all language constructs; the regex set above covers ~95% of cases. If you can't find a symbol, "(top-level)" is fine

## Why this exists

The default Grep tool returns hits without symbol context, so I usually have to Read each file to understand what the hit means. Inspired by jcode's `agentgrep` ([1jehuang/agentgrep](https://github.com/1jehuang/agentgrep)), which adds file-structure info to grep returns specifically so coding agents can infer more without reading the file. This is the same idea, ported to a Claude Code slash command.

If a hit is in a file you've already read this session, the symbol context is redundant, but it's still useful for the hits in unread files.
