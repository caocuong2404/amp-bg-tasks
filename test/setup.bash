# Common setup for all test files
# Creates isolated test environment with temp TASKS_DIR

TOOLBOX_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../toolbox" && pwd)"

setup() {
    # Each test gets its own temp tasks directory
    export TASKS_DIR="$(mktemp -d)"
    export TOOLBOX_ACTION="execute"
}

teardown() {
    # Kill any leftover background processes from tests
    if [[ -d "$TASKS_DIR" ]]; then
        for task_dir in "$TASKS_DIR"/task-*; do
            [[ -d "$task_dir" ]] || continue
            pid=$(cat "$task_dir/pid" 2>/dev/null || echo "0")
            if [[ "$pid" != "0" ]]; then
                kill "$pid" 2>/dev/null || true
                kill -9 "$pid" 2>/dev/null || true
            fi
            watchdog=$(cat "$task_dir/watchdog_pid" 2>/dev/null || echo "0")
            if [[ "$watchdog" != "0" ]]; then
                kill "$watchdog" 2>/dev/null || true
            fi
        done
        rm -rf "$TASKS_DIR"
    fi
}

# Helper: run a toolbox tool with JSON input
run_tool() {
    local tool="$1"
    local json="$2"
    echo "$json" | TOOLBOX_ACTION=execute TASKS_DIR="$TASKS_DIR" "$TOOLBOX_DIR/$tool"
}

# Helper: run describe mode
run_describe() {
    local tool="$1"
    TOOLBOX_ACTION=describe "$TOOLBOX_DIR/$tool"
}

# Helper: extract JSON field from output
json_field() {
    echo "$1" | jq -r "$2"
}

# Helper: wait for a task to finish (max 10s)
wait_for_task() {
    local task_id="$1"
    local max_wait=10
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        local status
        status=$(cat "$TASKS_DIR/$task_id/status" 2>/dev/null || echo "unknown")
        if [[ "$status" != "running" ]]; then
            return 0
        fi
        sleep 0.5
        waited=$((waited + 1))
    done
    return 1
}
