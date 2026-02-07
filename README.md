# amp-bg-tasks

Background task management toolbox for [Amp Code](https://ampcode.com) (by Sourcegraph).

Run long-running commands (dev servers, tests, builds) in the background and read their output with smart filtering — without polluting your agent's context window.

Inspired by [Claude Code's](https://claude.com/claude-code) `run_in_background` feature.

## The Problem

When debugging a monorepo, you need to run backend + frontend dev servers simultaneously. But if the agent reads raw server logs, thousands of noisy lines flood the context window — HMR updates, health checks, static asset requests, ANSI color codes, 300-character `node_modules/.pnpm/` paths.

**amp-bg-tasks** solves this with 4 toolbox tools that give your agent surgical control over background processes and their output. Tasks **auto-kill after 2 hours** by default, so you'll never have zombie dev servers running overnight.

## Tools

| Tool | Purpose |
|------|---------|
| `bg_run` | Start a command in the background, get a task ID |
| `bg_status` | List all tasks or check a specific task's status |
| `bg_output` | Smart log reader with auto-cleaning + filtering |
| `bg_stop` | Kill a running task or cleanup finished ones |

### `bg_output` — Smart Log Reader

The key tool. Output is **always auto-cleaned** before reaching the agent:

| Feature | What it does |
|---------|-------------|
| **Strip ANSI** | `\x1b[32minfo\x1b[39m` → `info` |
| **Shorten paths** | 300-char `.pnpm/@medusajs+draft-order@2.12.3_@medusajs+admin-sdk@...` → `.pnpm/@medusajs+draft-order@2.12.3_@.../` |
| **Truncate lines** | Lines >150 chars get `...[truncated]` |
| **Collapse repeats** | 5x "Using flag MEDUSA_FF_*" → 1 line + `... 4 similar lines collapsed` |
| **Filter** | `filter="error\|warn\|FAIL"` — only matching lines |
| **Exclude** | `exclude="GET 200\|HMR\|static"` — remove noise before filtering |
| **Incremental reads** | `since=true` — only new lines since last read (cursor-tracked) |
| **Safety cap** | `max_lines=80` default — hard limit on context usage |

### Real-World Impact

Tested on Medusa.js backend boot logs (35 lines, 4,471 chars):

| Mode | Chars | Reduction |
|------|-------|-----------|
| Raw (no toolbox) | 4,471 | — |
| Auto-cleaned | 2,131 | **52%** |
| Filtered (errors only) | 165 | **96%** |

## Install

### Quick Install

```bash
./install.sh
```

### Manual Install

1. Copy toolbox executables:
```bash
mkdir -p ~/.config/agents/toolbox
cp toolbox/* ~/.config/agents/toolbox/
chmod +x ~/.config/agents/toolbox/bg-*
```

2. Copy the skill:
```bash
mkdir -p ~/.config/agents/skills/background-tasks
cp skill/SKILL.md ~/.config/agents/skills/background-tasks/
```

3. Add AGENTS.md guidance (append to existing or create new):
```bash
cat agents/AGENTS.md >> ~/.config/agents/AGENTS.md
```

4. Install the reaper (auto-kills stale tasks on shell open):
```bash
mkdir -p ~/.local/bin
cp bg-reaper ~/.local/bin/
chmod +x ~/.local/bin/bg-reaper
```

5. Add to your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
# amp-bg-tasks
export AMP_TOOLBOX="$HOME/.config/agents/toolbox"
export PATH="$HOME/.local/bin:$PATH"
bg-reaper --max-age 180 2>/dev/null  # auto-kill stale tasks on shell open
```

6. Restart your shell and Amp.

## Usage

### Monorepo Dev (Backend + Frontend)

```
# Start both services
bg_run command="pnpm dev:backend" label="backend" cwd="/path/to/project"
bg_run command="pnpm dev:frontend" label="frontend" cwd="/path/to/project"

# Quick startup check
bg_output task_id="task-xxx" tail=5 stream="stderr"

# Debug errors only (NOT raw logs)
bg_output task_id="task-xxx" since=true filter="error|warn|FAIL" max_lines=30

# Stop when done
bg_stop task_id="task-xxx"
bg_stop action="cleanup"
```

### Run Tests While Fixing Code

```
bg_run command="npm test" label="tests"
# ... edit code ...
bg_output task_id="task-xxx" filter="FAIL|Error" tail=30
# ... fix failures ...
bg_run command="npm test" label="tests-v2"
```

### Parallel Operations

```
bg_run command="npm test" label="tests"
bg_run command="npm run lint" label="lint"
bg_run command="npm run build" label="build"
bg_status  # see all at once
```

### Watch Logs Incrementally

```
bg_run command="tail -f /var/log/app.log" label="logs"
# ... trigger action ...
bg_output task_id="task-xxx" since=true   # only new lines
# ... trigger another ...
bg_output task_id="task-xxx" since=true   # only newer lines
```

## Auto-Kill & Cleanup

No more zombie dev servers running overnight after you close your laptop.

### 3 layers of protection:

| Layer | What | When |
|-------|------|------|
| **Watchdog** (built into `bg_run`) | Each task auto-kills after `timeout` minutes | Default: 120m (2 hours). Set `timeout=0` to disable. |
| **Reaper** (`bg-reaper`) | Kills stale tasks + cleans old records on shell startup | Every time you open a terminal |
| **Status warnings** (`bg_status`) | Shows `age` and `auto_kill` countdown per task | Agent sees "EXPIRING in 5m" or "OVERDUE" |

### Timeout examples:

```
# Default: auto-kill after 2 hours
bg_run command="pnpm dev" label="dev-server"

# Long build: give it 4 hours
bg_run command="make build-all" label="build" timeout=240

# Quick test: kill after 10 minutes
bg_run command="npm test" label="tests" timeout=10

# Intentionally permanent: disable auto-kill
bg_run command="tail -f /var/log/syslog" label="syslog" timeout=0
```

### Reaper usage:

```bash
# Run manually
bg-reaper                     # kill tasks >3h old (default)
bg-reaper --max-age 60        # kill tasks >1h old
bg-reaper --dry-run            # preview what would be killed

# Auto-run on shell startup (add to ~/.zshrc)
bg-reaper --max-age 180 2>/dev/null
```

## Common Exclude Patterns

| Stack | Exclude pattern |
|-------|----------------|
| **Next.js** | `"HMR\|webpack\|static\|favicon\|_next\|compiled successfully"` |
| **Express/Node** | `"GET 200\|GET 304\|healthcheck\|OPTIONS"` |
| **Django** | `"GET /static\|200 OK\|Watching for\|StatReloader"` |
| **Rails** | `"Started GET.*assets\|200 OK\|Completed 200"` |
| **Vite** | `"hmr\|optimized\|pre-bundling\|static"` |
| **Medusa.js** | `"Using flag\|No .* to load from\|skipped"` |

## Requirements

- **Amp Code** (CLI or VS Code extension)
- `bash` (v4+)
- `jq` (for JSON parsing)
- macOS or Linux

## How It Works

Tasks are stored as simple files in `~/.local/state/amp-bg-tasks/`:

```
~/.local/state/amp-bg-tasks/
  task-1234567-890/
    command       # The command that was run
    pid           # Process ID
    label         # Human-readable label
    status        # running/completed/failed/killed
    stdout        # Standard output capture
    stderr        # Standard error capture
    exit_code     # Exit code (when done)
    started_at    # ISO timestamp
    finished_at   # ISO timestamp (when done)
    cwd           # Working directory
    .cursor_stdout # Incremental read cursor
```

No database, no daemon, no dependencies beyond bash + jq.

## Contributing

Contributions welcome! Some ideas:

- **New cleaning rules** — add patterns for your framework/stack
- **Better dedup** — improve the collapse_repeats algorithm
- **Notifications** — alert when a background task fails
- **Log rotation** — auto-truncate output files that grow too large
- **Multi-machine** — SSH-based remote task management
- **MCP server** — wrap as an MCP server for broader tool compatibility
- **Port to other agents** — adapt for Claude Code, Cursor, Windsurf, etc.

## License

MIT
