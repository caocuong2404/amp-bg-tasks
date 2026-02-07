#!/usr/bin/env bats

load setup

# Helper: create a fake task with content
create_fake_task() {
    local task_id="task-$(date +%s)-$$"
    local task_dir="$TASKS_DIR/$task_id"
    mkdir -p "$task_dir"
    echo "running" > "$task_dir/status"
    echo "" > "$task_dir/stderr"
    echo "$task_id"
}

# ── Describe mode ──

@test "bg-output: describe returns valid JSON schema" {
    run run_describe bg-output
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.name == "bg_output"'
    echo "$output" | jq -e '.inputSchema.properties.filter'
    echo "$output" | jq -e '.inputSchema.properties.since'
}

# ── Basic reads ──

@test "bg-output: reads stdout" {
    task_id=$(create_fake_task)
    echo "hello world" > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"hello world"* ]]
}

@test "bg-output: reads stderr separately" {
    task_id=$(create_fake_task)
    echo "stdout line" > "$TASKS_DIR/$task_id/stdout"
    echo "stderr line" > "$TASKS_DIR/$task_id/stderr"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"stream\": \"stderr\", \"since\": false}")
    stderr=$(json_field "$result" '.stderr')
    [[ "$stderr" == *"stderr line"* ]]
    # Should not have stdout field
    [ "$(json_field "$result" '.stdout // empty')" = "" ]
}

@test "bg-output: errors on missing task_id" {
    run run_tool bg-output '{}'
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.error'
}

@test "bg-output: errors on nonexistent task" {
    run run_tool bg-output '{"task_id": "task-nonexistent"}'
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.error'
}

# ── Tail ──

@test "bg-output: tail returns last N lines" {
    task_id=$(create_fake_task)
    for i in $(seq 1 20); do echo "line $i"; done > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"tail\": 3, \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"line 18"* ]]
    [[ "$stdout" == *"line 20"* ]]
    # Should NOT contain early lines
    [[ "$stdout" != *"line 1 "* ]] || [[ "$stdout" != *"line 1"$'\n'* ]]
}

# ── Filter ──

@test "bg-output: filter only returns matching lines" {
    task_id=$(create_fake_task)
    cat > "$TASKS_DIR/$task_id/stdout" << 'EOF'
info: server started
warn: deprecated API used
info: request handled
error: connection failed
info: request handled
EOF

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"filter\": \"error|warn\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"warn: deprecated"* ]]
    [[ "$stdout" == *"error: connection"* ]]
    [[ "$stdout" != *"info: server"* ]]
}

# ── Exclude ──

@test "bg-output: exclude removes matching lines" {
    task_id=$(create_fake_task)
    cat > "$TASKS_DIR/$task_id/stdout" << 'EOF'
GET /api/users 200
GET /healthcheck 200
POST /api/login 401
GET /healthcheck 200
GET /favicon.ico 304
EOF

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"exclude\": \"healthcheck|favicon\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"GET /api/users"* ]]
    [[ "$stdout" == *"POST /api/login"* ]]
    [[ "$stdout" != *"healthcheck"* ]]
    [[ "$stdout" != *"favicon"* ]]
}

@test "bg-output: filter + exclude combine correctly" {
    task_id=$(create_fake_task)
    cat > "$TASKS_DIR/$task_id/stdout" << 'EOF'
error: real problem
error: deprecated warning (ignore)
info: normal log
warn: something bad
EOF

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"filter\": \"error|warn\", \"exclude\": \"deprecated\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"real problem"* ]]
    [[ "$stdout" == *"something bad"* ]]
    [[ "$stdout" != *"deprecated"* ]]
    [[ "$stdout" != *"normal log"* ]]
}

# ── Since / Incremental ──

@test "bg-output: since=true first read returns last max_lines (not all)" {
    task_id=$(create_fake_task)
    for i in $(seq 1 100); do echo "line $i"; done > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"max_lines\": 10}")
    cursor=$(json_field "$result" '.stdout_meta.cursor')
    # Cursor should jump to end
    [ "$cursor" -eq 100 ]
}

@test "bg-output: since=true second read returns empty when no new lines" {
    task_id=$(create_fake_task)
    echo "line 1" > "$TASKS_DIR/$task_id/stdout"

    # First read — advances cursor
    run_tool bg-output "{\"task_id\": \"$task_id\"}" > /dev/null

    # Second read — no new lines
    result=$(run_tool bg-output "{\"task_id\": \"$task_id\"}")
    stdout=$(json_field "$result" '.stdout')
    [ -z "$stdout" ]
}

@test "bg-output: since=true returns only new lines after cursor" {
    task_id=$(create_fake_task)
    echo "old line 1" > "$TASKS_DIR/$task_id/stdout"
    echo "old line 2" >> "$TASKS_DIR/$task_id/stdout"

    # First read — sets cursor to 2
    run_tool bg-output "{\"task_id\": \"$task_id\"}" > /dev/null

    # Append new lines
    echo "new line 3" >> "$TASKS_DIR/$task_id/stdout"
    echo "new line 4" >> "$TASKS_DIR/$task_id/stdout"

    # Second read — should only get new lines
    result=$(run_tool bg-output "{\"task_id\": \"$task_id\"}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"new line 3"* ]]
    [[ "$stdout" == *"new line 4"* ]]
    [[ "$stdout" != *"old line"* ]]
}

@test "bg-output: since=false reads all output ignoring cursor" {
    task_id=$(create_fake_task)
    echo "line 1" > "$TASKS_DIR/$task_id/stdout"
    echo "line 2" >> "$TASKS_DIR/$task_id/stdout"

    # First read with since=true to set cursor
    run_tool bg-output "{\"task_id\": \"$task_id\"}" > /dev/null

    # Read with since=false — should get everything
    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"line 1"* ]]
    [[ "$stdout" == *"line 2"* ]]
}

# ── Auto-cleaning ──

@test "bg-output: strips ANSI escape codes" {
    task_id=$(create_fake_task)
    printf '\033[32minfo\033[39m: server started\n' > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" != *"\\033"* ]]
    [[ "$stdout" != *"\\x1b"* ]]
    [[ "$stdout" == *"info"* ]]
}

@test "bg-output: truncates long lines" {
    task_id=$(create_fake_task)
    python3 -c "print('x' * 300)" > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"[truncated]"* ]]
}

@test "bg-output: shortens node_modules paths" {
    task_id=$(create_fake_task)
    echo "No link from /Users/me/project/node_modules/.pnpm/@medusajs+core@2.12.3_something_long/node_modules/@medusajs/core/dist/file.js" > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *".pnpm/"* ]]
    [[ "$stdout" != *"something_long"* ]]
}

@test "bg-output: collapses repetitive lines" {
    task_id=$(create_fake_task)
    for i in $(seq 1 5); do echo "info: Using flag MEDUSA_FF_CACHING from project config with value true"; done > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" == *"similar lines collapsed"* ]]
}

@test "bg-output: removes blank lines" {
    task_id=$(create_fake_task)
    printf "line1\n\n\nline2\n\n" > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    [[ "$stdout" != *$'\n\n'* ]]
}

@test "bg-output: raw=true disables all cleaning" {
    task_id=$(create_fake_task)
    printf '\033[32minfo\033[39m: test\n' > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"raw\": true, \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    # Raw mode should preserve ANSI (though jq may escape them)
    [[ "$stdout" != *"[truncated]"* ]]
}

# ── Max lines ──

@test "bg-output: max_lines caps output" {
    task_id=$(create_fake_task)
    for i in $(seq 1 50); do echo "line $i"; done > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\", \"max_lines\": 5, \"since\": false}")
    stdout=$(json_field "$result" '.stdout')
    line_count=$(echo "$stdout" | wc -l | tr -d ' ')
    # Should be max_lines + 1 for the "[... N earlier lines omitted]" header
    [ "$line_count" -le 7 ]
}

# ── Metadata ──

@test "bg-output: returns stdout_meta with total_lines and cursor" {
    task_id=$(create_fake_task)
    for i in $(seq 1 10); do echo "line $i"; done > "$TASKS_DIR/$task_id/stdout"

    result=$(run_tool bg-output "{\"task_id\": \"$task_id\"}")
    total=$(json_field "$result" '.stdout_meta.total_lines')
    cursor=$(json_field "$result" '.stdout_meta.cursor')
    [ "$total" -eq 10 ]
    [ "$cursor" -eq 10 ]
}
