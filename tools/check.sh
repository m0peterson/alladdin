#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v timeout >/dev/null || { echo 'BLOCKED: отсутствует timeout.' >&2; exit 1; }
mkdir -p "$project_dir/.godot/check-logs"
"$project_dir/tools/godot.sh" --version

run_check() {
    local name="$1"
    shift
    local log="$project_dir/.godot/check-logs/$name.log"
    local status=0
    timeout 60s "$project_dir/tools/godot.sh" "$@" >"$log" 2>&1 || status=$?
    cat "$log"
    if (( status != 0 )); then
        echo "FAIL: $name (exit $status)." >&2
        return "$status"
    fi
    if grep -Eq '(SCRIPT ERROR|ERROR):' "$log"; then
        echo "FAIL: $name содержит ошибки Godot." >&2
        return 1
    fi
    echo "PASS: $name."
}

run_check import --headless --editor --import
run_check startup --headless --quit-after 3
run_check settings --headless --script res://tools/check_startup.gd
if ! grep -Fq 'PASS: T01 startup and settings' "$project_dir/.godot/check-logs/settings.log"; then
    echo 'FAIL: проверка стартовой сцены не завершилась.' >&2
    exit 1
fi
