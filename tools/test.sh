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

log="$project_dir/.godot/check-logs/bazaar.log"
status=0
timeout 90s "$project_dir/tools/godot.sh" --headless --fixed-fps 60 \
    --script res://tests/check_bazaar.gd >"$log" 2>&1 || status=$?
cat "$log"
if (( status != 0 )); then
    echo "FAIL: T03 bazaar (exit $status)." >&2
    exit "$status"
fi
if grep -Eq '(SCRIPT ERROR|ERROR):' "$log" || ! grep -Fq 'PASS: T03 bazaar routes, zones, walls, NPC collisions and foot anchors' "$log"; then
    echo 'FAIL: сценарий T03 содержит ошибки или не завершился.' >&2
    exit 1
fi

log="$project_dir/.godot/check-logs/ui.log"
status=0
timeout 60s "$project_dir/tools/godot.sh" --headless --fixed-fps 60 \
    --script res://tests/check_ui.gd >"$log" 2>&1 || status=$?
cat "$log"
if (( status != 0 )); then
    echo "FAIL: T04 UI (exit $status)." >&2
    exit "$status"
fi
if grep -Eq '(SCRIPT ERROR|ERROR):' "$log" || ! grep -Fq 'PASS: T04 menus, shared HUD state, pause and input isolation' "$log"; then
    echo 'FAIL: сценарий T04 содержит ошибки или не завершился.' >&2
    exit 1
fi

log="$project_dir/.godot/check-logs/interaction.log"
status=0
timeout 60s "$project_dir/tools/godot.sh" --headless --fixed-fps 60 \
    --script res://tests/check_interaction.gd >"$log" 2>&1 || status=$?
cat "$log"
if (( status != 0 )); then
    echo "FAIL: T05 interaction (exit $status)." >&2
    exit "$status"
fi
if grep -Eq '(SCRIPT ERROR|ERROR):' "$log" || ! grep -Fq 'PASS: T05 interaction' "$log"; then
    echo 'FAIL: сценарий T05 содержит ошибки или не завершился.' >&2
    exit 1
fi

run_scenario() {
    local name="$1" script="$2" marker="$3"
    local scenario_log="$project_dir/.godot/check-logs/$name.log"
    local scenario_status=0
    timeout 60s "$project_dir/tools/godot.sh" --headless --fixed-fps 60 \
        --script "res://tests/$script" >"$scenario_log" 2>&1 || scenario_status=$?
    cat "$scenario_log"
    if (( scenario_status != 0 )); then
        echo "FAIL: $name (exit $scenario_status)." >&2
        return "$scenario_status"
    fi
    if grep -Eq '(SCRIPT ERROR|ERROR):' "$scenario_log" || ! grep -Fq "$marker" "$scenario_log"; then
        echo "FAIL: $name содержит ошибки или не завершился." >&2
        return 1
    fi
}

run_scenario inventory check_inventory.gd 'PASS: T06'
run_scenario trade check_trade.gd 'PASS: T07'
run_scenario combat check_combat.gd 'PASS: T08'
run_scenario bandit check_bandit.gd 'PASS: T09'
run_scenario patrol check_patrol.gd 'PASS: T10'
run_scenario integration check_t05_t10.gd 'PASS: T05–T10 integration'
