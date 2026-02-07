#!/usr/bin/env bash
# install.sh — Install amp-bg-tasks toolbox, skill, and AGENTS.md guidance
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLBOX_DIR="${HOME}/.config/agents/toolbox"
SKILL_DIR="${HOME}/.config/agents/skills/background-tasks"
AGENTS_FILE="${HOME}/.config/agents/AGENTS.md"

echo "Installing amp-bg-tasks..."
echo ""

# 1. Toolbox executables
echo "[1/3] Installing toolbox tools → ${TOOLBOX_DIR}/"
mkdir -p "$TOOLBOX_DIR"
cp "$SCRIPT_DIR/toolbox/bg-run" "$TOOLBOX_DIR/"
cp "$SCRIPT_DIR/toolbox/bg-output" "$TOOLBOX_DIR/"
cp "$SCRIPT_DIR/toolbox/bg-status" "$TOOLBOX_DIR/"
cp "$SCRIPT_DIR/toolbox/bg-stop" "$TOOLBOX_DIR/"
chmod +x "$TOOLBOX_DIR"/bg-*
echo "  Installed: bg-run, bg-output, bg-status, bg-stop"

# 2. Skill
echo "[2/3] Installing skill → ${SKILL_DIR}/"
mkdir -p "$SKILL_DIR"
cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/"
echo "  Installed: SKILL.md"

# 3. AGENTS.md
echo "[3/3] Updating AGENTS.md → ${AGENTS_FILE}"
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

# 4. Create task storage directory
mkdir -p "${HOME}/.local/state/amp-bg-tasks"

echo ""
echo "Done! Next steps:"
echo ""
echo "  1. Add to your shell profile (~/.zshrc or ~/.bashrc):"
echo "     export AMP_TOOLBOX=\"\$HOME/.config/agents/toolbox\""
echo ""
echo "  2. Restart Amp"
echo ""
echo "  3. Try it: ask Amp to 'run npm test in the background'"
