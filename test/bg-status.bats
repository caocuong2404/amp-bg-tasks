#!/usr/bin/env bats

load setup

# ── Describe mode ──

@test "bg-status: describe returns valid JSON schema" {
    run run_describe bg-status
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.name == "bg_status"'
}

# ── List all tasks ──

@test "bg-status: returns empty list when no tasks" {
    result=$(run_tool bg-status '{}')
    total=$(json_field "$result" '.summary.total')
    [ "$total" -eq 0 ]
}

@test "bg-status: lists running tasks" {
    # Start a task
    bg_result=$(run_tool bg-run '{"command": "sleep 30", "label": "test-task"}')
    task_id=$(json_field "$bg_result" '.task_id')
    sleep 0.3

    result=$(run_tool bg-status '{}')
    total=$(json_field "$result" '.summary.total')
    running=$(json_field "$result" '.summary.running')
    [ "$total" -ge 1 ]
    [ "$running" -ge 1 ]

    # Check the task appears in the list
    label=$(echo "$result" | jq -r ".tasks[] | select(.task_id == \"$task_id\") | .label")
    [ "$label" = "test-task" ]
}

@test "bg-status: shows age for tasks" {
    bg_result=$(run_tool bg-run '{"command": "sleep 30", "label": "age-test"}')
    task_id=$(json_field "$bg_result" '.task_id')
    sleep 0.3

    result=$(run_tool bg-status "{\"task_id\": \"$task_id\"}")
    age=$(json_field "$result" '.age')
    [ -n "$age" ]
    [[ "$age" == *"m"* ]]
}

@test "bg-status: shows auto_kill countdown" {
    bg_result=$(run_tool bg-run '{"command": "sleep 30", "label": "timeout-test", "timeout": 60}')
    task_id=$(json_field "$bg_result" '.task_id')
    sleep 0.3

    result=$(run_tool bg-status "{\"task_id\": \"$task_id\"}")
    auto_kill=$(json_field "$result" '.auto_kill')
    [[ "$auto_kill" == *"left"* ]]
    timeout=$(json_field "$result" '.timeout_minutes')
    [ "$timeout" -eq 60 ]
}

# ── Single task ──

@test "bg-status: shows detailed status for specific task" {
    bg_result=$(run_tool bg-run '{"command": "echo done", "label": "detail-test"}')
    task_id=$(json_field "$bg_result" '.task_id')
    wait_for_task "$task_id"

    result=$(run_tool bg-status "{\"task_id\": \"$task_id\"}")
    [ "$(json_field "$result" '.status')" = "completed" ]
    [ "$(json_field "$result" '.label')" = "detail-test" ]
    [ "$(json_field "$result" '.exit_code')" = "0" ]
    [ "$(json_field "$result" '.stdout_lines')" -ge 0 ]
}

@test "bg-status: errors on nonexistent task" {
    run run_tool bg-status '{"task_id": "task-nonexistent"}'
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.error'
}

# ── Zombie detection ──

@test "bg-status: detects dead process and updates status" {
    # Create a fake running task with a dead PID
    task_id="task-$(date +%s)-$$"
    task_dir="$TASKS_DIR/$task_id"
    mkdir -p "$task_dir"
    echo "running" > "$task_dir/status"
    echo "99999999" > "$task_dir/pid"
    echo "sleep 999" > "$task_dir/command"
    echo "zombie-test" > "$task_dir/label"
    echo "120" > "$task_dir/timeout"
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$task_dir/started_at"
    echo "" > "$task_dir/stdout"
    echo "" > "$task_dir/stderr"

    result=$(run_tool bg-status "{\"task_id\": \"$task_id\"}")
    status_val=$(json_field "$result" '.status')
    # Should detect the dead PID and update status
    [ "$status_val" = "killed" ]
}
