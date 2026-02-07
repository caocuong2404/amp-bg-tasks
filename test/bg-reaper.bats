#!/usr/bin/env bats

load setup

REAPER="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/bg-reaper"

# Override setup to create proper HOME structure for reaper
setup() {
    export FAKE_HOME="$(mktemp -d)"
    export TASKS_DIR="$FAKE_HOME/.local/state/amp-bg-tasks"
    mkdir -p "$TASKS_DIR"
    export TOOLBOX_ACTION="execute"
}

teardown() {
    # Kill leftover processes
    if [[ -d "$TASKS_DIR" ]]; then
        for task_dir in "$TASKS_DIR"/task-*; do
            [[ -d "$task_dir" ]] || continue
            pid=$(cat "$task_dir/pid" 2>/dev/null || echo "0")
            [[ "$pid" != "0" ]] && kill "$pid" 2>/dev/null || true
        done
    fi
    rm -rf "$FAKE_HOME"
}

# Helper: create a fake task with custom age
create_task_with_age() {
    local age_minutes="${1:-200}"
    local status="${2:-running}"
    local stale_epoch=$(($(date +%s) - age_minutes * 60))
    local task_id="task-${stale_epoch}-$$"
    local task_dir="$TASKS_DIR/$task_id"
    mkdir -p "$task_dir"
    echo "$status" > "$task_dir/status"
    echo "99999999" > "$task_dir/pid"
    echo "sleep 999" > "$task_dir/command"
    echo "${3:-test-task}" > "$task_dir/label"
    echo "120" > "$task_dir/timeout"
    echo "" > "$task_dir/stdout"
    echo "" > "$task_dir/stderr"
    echo "$task_id"
}

@test "bg-reaper: dry-run shows stale running tasks to kill" {
    create_task_with_age 200 "running" "stale-runner"

    run env HOME="$FAKE_HOME" "$REAPER" --max-age 60 --dry-run
    [[ "$output" == *"Would kill"* ]]
}

@test "bg-reaper: dry-run shows old finished tasks to clean" {
    create_task_with_age 200 "completed" "old-done"

    run env HOME="$FAKE_HOME" "$REAPER" --max-age 60 --dry-run
    [[ "$output" == *"Would clean"* ]]
}

@test "bg-reaper: leaves fresh running tasks with live PID alone" {
    # Create a fresh task with a LIVE process (not a dead PID)
    sleep 300 &
    local live_pid=$!

    local fresh_epoch=$(date +%s)
    local task_id="task-${fresh_epoch}-$$"
    local task_dir="$TASKS_DIR/$task_id"
    mkdir -p "$task_dir"
    echo "running" > "$task_dir/status"
    echo "$live_pid" > "$task_dir/pid"
    echo "sleep 300" > "$task_dir/command"
    echo "fresh-task" > "$task_dir/label"
    echo "120" > "$task_dir/timeout"
    echo "" > "$task_dir/stdout"
    echo "" > "$task_dir/stderr"

    run env HOME="$FAKE_HOME" "$REAPER" --max-age 180 --dry-run
    [[ "$output" != *"fresh-task"* ]]

    kill "$live_pid" 2>/dev/null || true
}

@test "bg-reaper: actually kills stale tasks (not dry-run)" {
    task_id=$(create_task_with_age 200 "running" "kill-me")

    env HOME="$FAKE_HOME" "$REAPER" --max-age 60
    status=$(cat "$TASKS_DIR/$task_id/status" 2>/dev/null || echo "gone")
    [ "$status" = "reaped" ]
}

@test "bg-reaper: actually removes old finished tasks" {
    task_id=$(create_task_with_age 200 "completed" "clean-me")
    [ -d "$TASKS_DIR/$task_id" ]

    env HOME="$FAKE_HOME" "$REAPER" --max-age 60
    [ ! -d "$TASKS_DIR/$task_id" ]
}

@test "bg-reaper: --help shows usage" {
    run "$REAPER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--max-age"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "bg-reaper: exits cleanly with no tasks dir" {
    run env HOME="/tmp/nonexistent-reaper-$$" "$REAPER"
    [ "$status" -eq 0 ]
}
