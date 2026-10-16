#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v timeout >/dev/null || { echo 'BLOCKED: отсутствует timeout.' >&2; exit 1; }
mkdir -p "$project_dir/.godot/check-logs"
log="$project_dir/.godot/check-logs/movement.log"
status=0
timeout 60s "$project_dir/tools/godot.sh" --headless --fixed-fps 60 \
    --script res://tests/check_movement.gd >"$log" 2>&1 || status=$?
cat "$log"
if (( status != 0 )); then
    echo "FAIL: T02 movement (exit $status)." >&2
    exit "$status"
fi
if grep -Eq '(SCRIPT ERROR|ERROR):' "$log" || ! grep -Fq 'PASS: T02 movement, collisions, facing and sprite foot baseline' "$log"; then
    echo 'FAIL: сценарий T02 содержит ошибки или не завершился.' >&2
    exit 1
fi
