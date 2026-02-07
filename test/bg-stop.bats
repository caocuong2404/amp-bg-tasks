#!/usr/bin/env bats

load setup

# ── Describe mode ──

@test "bg-stop: describe returns valid JSON schema" {
    run run_describe bg-stop
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.name == "bg_stop"'
}

# ── Kill action ──

@test "bg-stop: kills a running task" {
    bg_result=$(run_tool bg-run '{"command": "sleep 60", "label": "kill-test"}')
    task_id=$(json_field "$bg_result" '.task_id')
    pid=$(json_field "$bg_result" '.pid')
    sleep 0.5

    # Verify it's running
    kill -0 "$pid" 2>/dev/null
    [ $? -eq 0 ]

    # Kill it
    result=$(run_tool bg-stop "{\"task_id\": \"$task_id\"}")
    [ "$(json_field "$result" '.status')" = "killed" ]

    sleep 1
    # Verify process is dead
    ! kill -0 "$pid" 2>/dev/null
}

@test "bg-stop: updates status file to killed" {
    bg_result=$(run_tool bg-run '{"command": "sleep 60"}')
    task_id=$(json_field "$bg_result" '.task_id')
    sleep 0.5

    run_tool bg-stop "{\"task_id\": \"$task_id\"}" > /dev/null

    [ "$(cat "$TASKS_DIR/$task_id/status")" = "killed" ]
    [ "$(cat "$TASKS_DIR/$task_id/exit_code")" = "137" ]
    [ -f "$TASKS_DIR/$task_id/finished_at" ]
}

@test "bg-stop: reports already-finished task" {
    bg_result=$(run_tool bg-run '{"command": "echo done"}')
    task_id=$(json_field "$bg_result" '.task_id')
    wait_for_task "$task_id"

    result=$(run_tool bg-stop "{\"task_id\": \"$task_id\"}")
    [[ "$(json_field "$result" '.message')" == *"not running"* ]]
}

@test "bg-stop: errors on missing task_id" {
    run run_tool bg-stop '{"action": "kill"}'
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.error'
}

@test "bg-stop: errors on nonexistent task" {
    run run_tool bg-stop '{"task_id": "task-nonexistent"}'
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.error'
}

# ── Cleanup action ──

@test "bg-stop: cleanup removes finished tasks" {
    # Create completed task
    bg_result=$(run_tool bg-run '{"command": "echo done"}')
    task_id=$(json_field "$bg_result" '.task_id')
    wait_for_task "$task_id"

    # Verify it exists
    [ -d "$TASKS_DIR/$task_id" ]

    # Cleanup
    result=$(run_tool bg-stop '{"action": "cleanup"}')
    cleaned=$(json_field "$result" '.cleaned')
    [ "$cleaned" -ge 1 ]

    # Verify it's gone
    [ ! -d "$TASKS_DIR/$task_id" ]
}

@test "bg-stop: cleanup preserves running tasks" {
    # Start a long task
    bg_result=$(run_tool bg-run '{"command": "sleep 60", "label": "keep-me"}')
    running_id=$(json_field "$bg_result" '.task_id')
    sleep 0.3

    # Create and complete another task
    bg_result2=$(run_tool bg-run '{"command": "echo done"}')
    done_id=$(json_field "$bg_result2" '.task_id')
    wait_for_task "$done_id"

    # Cleanup
    run_tool bg-stop '{"action": "cleanup"}' > /dev/null

    # Running task should still exist
    [ -d "$TASKS_DIR/$running_id" ]
    # Completed task should be gone
    [ ! -d "$TASKS_DIR/$done_id" ]
}

@test "bg-stop: cleanup returns 0 when nothing to clean" {
    result=$(run_tool bg-stop '{"action": "cleanup"}')
    cleaned=$(json_field "$result" '.cleaned')
    [ "$cleaned" -eq 0 ]
}
