---
name: background-tasks
description: "Run and monitor background tasks for debugging. Start tests, builds, dev servers, or any long-running command in the background while continuing to work. Smart log reading with filtering, incremental reads, and noise exclusion to keep context clean."
---

# Background Tasks

Run commands in the background and monitor their output — useful for debugging, running tests, builds, and dev servers without blocking the main conversation.

## Available Tools

| Tool | Purpose |
|------|---------|
| `bg_run` | Start a command in the background, get a task ID |
| `bg_status` | List all tasks or check a specific task's status |
| `bg_output` | Smart log reader with filter/exclude/since/tail to avoid context mess |
| `bg_stop` | Kill a running task or clean up finished task records |

## Smart Log Reading (Context-Safe)

`bg_output` is designed to prevent context pollution from noisy logs. **ALWAYS use filtering params** when reading logs from dev servers or verbose processes:

| Param | What it does | Example |
|-------|-------------|---------|
| `filter` | Only return lines matching regex | `"ERROR\|WARN\|Exception\|FAIL\|panic"` |
| `exclude` | Remove noisy lines before reading | `"GET 200\|HMR\|static\|healthcheck\|favicon\|webpack"` |
| `since` | Only new lines since last read (incremental) | `true` — perfect for polling |
| `tail` | Last N lines only | `30` — quick check |
| `max_lines` | Safety cap (default 200) | `50` — tight context budget |

**Combine them**: `filter="ERROR\|WARN" exclude="deprecated" since=true max_lines=50`

The response includes `stdout_meta` / `stderr_meta` with `total_lines` and `cursor` so you know how much output exists vs. what you've read.

## Monorepo Pattern: Backend + Frontend

This is the key use case. Run both services, debug without log noise:

```
# Step 1: Start both services
bg_run command="cd apps/backend && npm run dev" label="backend"    → task-aaa
bg_run command="cd apps/frontend && npm run dev" label="frontend"  → task-bbb

# Step 2: Work on code changes...

# Step 3: Check for errors only (NOT raw logs)
bg_output task_id="task-aaa" filter="ERROR|WARN|Exception" exclude="GET 200|healthcheck" tail=30
bg_output task_id="task-bbb" filter="ERROR|error|FAIL" exclude="HMR|webpack|static|favicon" tail=30

# Step 4: After making a change, check only NEW output
bg_output task_id="task-aaa" since=true filter="ERROR|WARN"
bg_output task_id="task-bbb" since=true filter="ERROR|error"

# Step 5: If something breaks, read more context around the error
bg_output task_id="task-aaa" stream="stderr" tail=50

# Step 6: Cleanup when done
bg_stop task_id="task-aaa"
bg_stop task_id="task-bbb"
bg_stop action="cleanup"
```

### Common Exclude Patterns by Stack

| Stack | Exclude pattern |
|-------|----------------|
| **Next.js** | `"HMR\|webpack\|static\|favicon\|_next\|compiled successfully"` |
| **Express/Node** | `"GET 200\|GET 304\|healthcheck\|OPTIONS"` |
| **Django** | `"GET /static\|200 OK\|Watching for\|StatReloader"` |
| **Rails** | `"Started GET.*assets\|200 OK\|Completed 200"` |
| **Vite** | `"hmr\|optimized\|pre-bundling\|static"` |
| **General** | `"GET 200\|healthcheck\|favicon\|static\|HMR\|hot.update"` |

## Other Workflow Patterns

### Run Tests While Fixing Code

```
1. bg_run command="npm test" label="tests"
2. ... continue editing files ...
3. bg_status task_id="task-xxx"                              → check if done
4. bg_output task_id="task-xxx" filter="FAIL|Error" tail=30  → see only failures
5. ... fix the failures ...
6. bg_run command="npm test" label="tests-v2"                → re-run
```

### Parallel Operations

```
1. bg_run command="npm test" label="tests"
2. bg_run command="npm run lint" label="lint"
3. bg_run command="npm run build" label="build"
4. bg_status                                → see all tasks at once
5. bg_output task_id="..." filter="error|FAIL" for each
```

### Watch Logs Incrementally

```
1. bg_run command="tail -f /var/log/app.log" label="logs"
2. ... trigger some action ...
3. bg_output task_id="task-xxx" since=true                  → only new lines
4. ... trigger another action ...
5. bg_output task_id="task-xxx" since=true                  → only newer lines
6. bg_stop task_id="task-xxx"
```

## Rules for Context Hygiene

1. **NEVER read raw logs from a dev server** — always use `filter` or `tail`
2. **Use `since=true`** when polling — avoid re-reading the same 10,000 lines
3. **Set `max_lines`** when unsure about output size (default 200 is usually enough)
4. **Use `stream="stderr"`** to focus on errors, skip access logs on stdout
5. **Use `exclude`** to strip noise BEFORE filtering — keeps results surgical
6. **Check `stdout_meta.total_lines`** in response — if it says 50,000 lines, definitely don't read raw

## Tips

- Always use a descriptive `label` so tasks are easy to identify
- Use `bg_stop action="cleanup"` periodically to remove old finished tasks
- Task data is stored in `~/.local/state/amp-bg-tasks/`
- Use `cwd` parameter in `bg_run` if the command needs a specific working directory
