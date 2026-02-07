#!/usr/bin/env bats

load setup

# ── Describe mode ──

@test "bg-run: describe returns valid JSON schema" {
    run run_describe bg-run
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.name == "bg_run"'
    echo "$output" | jq -e '.inputSchema.properties.command'
    echo "$output" | jq -e '.inputSchema.properties.timeout'
}

# ── Basic execution ──

@test "bg-run: starts a command and returns task ID" {
    run run_tool bg-run '{"command": "echo hello"}'
    [ "$status" -eq 0 ]
    task_id=$(json_field "$output" '.task_id')
    [[ "$task_id" == task-* ]]
}

@test "bg-run: returns correct metadata" {
    run run_tool bg-run '{"command": "echo test", "label": "my-label"}'
    [ "$status" -eq 0 ]
    [ "$(json_field "$output" '.label')" = "my-label" ]
    [ "$(json_field "$output" '.status')" = "running" ]
    [ "$(json_field "$output" '.command')" = "echo test" ]
    pid=$(json_field "$output" '.pid')
    [ "$pid" -gt 0 ]
}

@test "bg-run: captures stdout" {
    result=$(run_tool bg-run '{"command": "echo hello-world"}')
    task_id=$(json_field "$result" '.task_id')
    wait_for_task "$task_id"

    stdout=$(cat "$TASKS_DIR/$task_id/stdout")
    [ "$stdout" = "hello-world" ]
}

@test "bg-run: captures stderr" {
    result=$(run_tool bg-run '{"command": "echo error-msg >&2"}')
    task_id=$(json_field "$result" '.task_id')
    wait_for_task "$task_id"

    stderr=$(cat "$TASKS_DIR/$task_id/stderr")
    [ "$stderr" = "error-msg" ]
}

@test "bg-run: sets status to completed on success" {
    result=$(run_tool bg-run '{"command": "echo ok"}')
    task_id=$(json_field "$result" '.task_id')
    wait_for_task "$task_id"

    [ "$(cat "$TASKS_DIR/$task_id/status")" = "completed" ]
    [ "$(cat "$TASKS_DIR/$task_id/exit_code")" = "0" ]
}

@test "bg-run: sets status to failed on error" {
    result=$(run_tool bg-run '{"command": "exit 42"}')
    task_id=$(json_field "$result" '.task_id')
    wait_for_task "$task_id"

    [ "$(cat "$TASKS_DIR/$task_id/status")" = "failed" ]
    [ "$(cat "$TASKS_DIR/$task_id/exit_code")" = "42" ]
}

@test "bg-run: errors when command is missing" {
    run run_tool bg-run '{"label": "no-cmd"}'
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.error'
}

@test "bg-run: uses custom cwd" {
    result=$(run_tool bg-run '{"command": "pwd", "cwd": "/tmp"}')
    task_id=$(json_field "$result" '.task_id')
    wait_for_task "$task_id"

    stdout=$(cat "$TASKS_DIR/$task_id/stdout")
    [[ "$stdout" == *"/tmp"* ]] || [[ "$stdout" == *"/private/tmp"* ]]
}

@test "bg-run: default label is task_id" {
    result=$(run_tool bg-run '{"command": "echo x"}')
    task_id=$(json_field "$result" '.task_id')
    label=$(cat "$TASKS_DIR/$task_id/label")
    [ "$label" = "$task_id" ]
}

# ── Timeout / Watchdog ──

@test "bg-run: stores timeout in metadata" {
    result=$(run_tool bg-run '{"command": "sleep 999", "timeout": 60}')
    task_id=$(json_field "$result" '.task_id')

    [ "$(cat "$TASKS_DIR/$task_id/timeout")" = "60" ]
    [ "$(json_field "$result" '.timeout_minutes')" = "60" ]
}

@test "bg-run: default timeout is 120 minutes" {
    result=$(run_tool bg-run '{"command": "echo x"}')
    task_id=$(json_field "$result" '.task_id')

    [ "$(cat "$TASKS_DIR/$task_id/timeout")" = "120" ]
}

@test "bg-run: timeout=0 disables auto-kill" {
    result=$(run_tool bg-run '{"command": "echo x", "timeout": 0}')
    [ "$(json_field "$result" '.timeout_minutes')" = "0" ]
    [[ "$(json_field "$result" '.message')" == *"No auto-kill"* ]]
}

@test "bg-run: creates watchdog pid file when timeout > 0" {
    result=$(run_tool bg-run '{"command": "sleep 999", "timeout": 5}')
    task_id=$(json_field "$result" '.task_id')
    sleep 0.5

    [ -f "$TASKS_DIR/$task_id/watchdog_pid" ]
    watchdog_pid=$(cat "$TASKS_DIR/$task_id/watchdog_pid")
    [ "$watchdog_pid" -gt 0 ]
}

@test "bg-run: creates timestamps" {
    result=$(run_tool bg-run '{"command": "echo x"}')
    task_id=$(json_field "$result" '.task_id')

    started=$(cat "$TASKS_DIR/$task_id/started_at")
    [[ "$started" == *"T"*"Z" ]]
}
