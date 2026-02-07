## Background Tasks

You have background task tools via toolbox: `bg_run`, `bg_status`, `bg_output`, `bg_stop`.

**Prefer `bg_run` over regular Bash** for any command that takes more than a few seconds (tests, builds, servers, installs).

### MANDATORY rules for `bg_output`:

1. **NEVER call `bg_output` without `filter` or `tail` on a running dev server.** Raw server logs will pollute your context window. Always use `filter="error|Error|ERROR|warn|WARN|fail|FAIL|Exception|panic"`.
2. **Use `since=true`** when polling a running process — never re-read old output.
3. **Use `tail=20`** for quick status checks (is the server up?).
4. **Keep `max_lines` low** — default is 80, use 30 for routine checks.
5. Output is auto-cleaned (ANSI stripped, long paths shortened, repetitive lines collapsed), but filtering is still YOUR responsibility.

### Quick reference:
- `bg_run` — start a background command (always set a `label`)
- `bg_status` — list all tasks or check one
- `bg_output` — read output (**always** use `filter` + `since` for servers)
- `bg_stop` — kill a task or `action="cleanup"` to clear finished tasks

### Example — monorepo dev:
```
bg_run command="pnpm dev:backend" label="backend" cwd="..."
bg_run command="pnpm dev:frontend" label="frontend" cwd="..."

# Quick startup check (is it up yet?)
bg_output task_id="..." tail=5 stream="stderr"

# Debug errors only
bg_output task_id="..." since=true filter="error|Error|warn|WARN" max_lines=30

# WRONG — never do this on a dev server:
# bg_output task_id="..." tail=60 max_lines=60  ← context pollution
```
