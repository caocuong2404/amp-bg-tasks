#!/usr/bin/env bash
# install.sh — Install amp-bg-tasks toolbox, skill, AGENTS.md guidance, and reaper
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLBOX_DIR="${HOME}/.config/agents/toolbox"
SKILL_DIR="${HOME}/.config/agents/skills/background-tasks"
AGENTS_FILE="${HOME}/.config/agents/AGENTS.md"
BIN_DIR="${HOME}/.local/bin"

echo "Installing amp-bg-tasks..."
echo ""

# 1. Toolbox executables
echo "[1/4] Installing toolbox tools → ${TOOLBOX_DIR}/"
mkdir -p "$TOOLBOX_DIR"
cp "$SCRIPT_DIR/toolbox/bg-run" "$TOOLBOX_DIR/"
cp "$SCRIPT_DIR/toolbox/bg-output" "$TOOLBOX_DIR/"
cp "$SCRIPT_DIR/toolbox/bg-status" "$TOOLBOX_DIR/"
cp "$SCRIPT_DIR/toolbox/bg-stop" "$TOOLBOX_DIR/"
chmod +x "$TOOLBOX_DIR"/bg-*
echo "  Installed: bg-run, bg-output, bg-status, bg-stop"

# 2. Skill
echo "[2/4] Installing skill → ${SKILL_DIR}/"
mkdir -p "$SKILL_DIR"
cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/"
echo "  Installed: SKILL.md"

# 3. AGENTS.md
echo "[3/4] Updating AGENTS.md → ${AGENTS_FILE}"
if [[ -f "$AGENTS_FILE" ]]; then
    if grep -q "bg_run\|bg_output\|bg_status\|bg_stop\|amp-bg-tasks" "$AGENTS_FILE" 2>/dev/null; then
        echo "  AGENTS.md already contains background task guidance. Skipping."
    else
        echo "" >> "$AGENTS_FILE"
        cat "$SCRIPT_DIR/agents/AGENTS.md" >> "$AGENTS_FILE"
        echo "  Appended background task guidance to existing AGENTS.md"
    fi
else
    cp "$SCRIPT_DIR/agents/AGENTS.md" "$AGENTS_FILE"
    echo "  Created AGENTS.md with background task guidance"
fi

# 4. Reaper (auto-cleanup on shell startup)
echo "[4/4] Installing bg-reaper → ${BIN_DIR}/"
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/bg-reaper" "$BIN_DIR/"
chmod +x "$BIN_DIR/bg-reaper"
echo "  Installed: bg-reaper"

# 5. Create task storage directory
mkdir -p "${HOME}/.local/state/amp-bg-tasks"

echo ""
echo "Done! Add these to your shell profile (~/.zshrc or ~/.bashrc):"
echo ""
echo "  # amp-bg-tasks"
echo "  export AMP_TOOLBOX=\"\$HOME/.config/agents/toolbox\""
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "  bg-reaper --max-age 180 2>/dev/null  # auto-kill stale tasks on shell open"
echo ""
echo "Then restart your shell and Amp."
echo ""
echo "What it does:"
echo "  - bg_run: tasks auto-kill after 2 hours (configurable via timeout param)"
echo "  - bg-reaper: kills any leftover tasks >3 hours old every time you open a terminal"
echo "  - bg_status: shows age + countdown for every task"
