#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$project_dir/.godot/cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$project_dir/.godot/user-data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$project_dir/.godot/config}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

if [[ -n "${GODOT_BIN:-}" ]]; then
    candidates=("$GODOT_BIN")
else
    candidates=(
        "$project_dir/.tools/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
        godot
        godot4
    )
fi

for candidate in "${candidates[@]}"; do
    if [[ "$candidate" != */* ]]; then
        candidate="$(command -v "$candidate" || true)"
    fi
    [[ -x "$candidate" ]] || continue
    if version="$("$candidate" --version)"; then
        if [[ "$version" == 4.7.2.stable.* && "$version" != *mono* ]]; then
            exec "$candidate" --path "$project_dir" "$@"
        fi
    fi
done

echo 'BLOCKED: нужен Godot 4.7.2 stable standard.' >&2
echo 'Запустите tools/bootstrap-godot.sh или задайте GODOT_BIN для нужного бинарника.' >&2
exit 1
