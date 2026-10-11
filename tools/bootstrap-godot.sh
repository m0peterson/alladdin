#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if "$project_dir/tools/godot.sh" --version >/dev/null 2>&1; then
    echo 'PASS: Godot 4.7.2 stable standard уже доступен.'
    exit 0
fi
if [[ -n "${GODOT_BIN:-}" ]]; then
    echo 'BLOCKED: GODOT_BIN задан, но не указывает на Godot 4.7.2 stable standard.' >&2
    exit 1
fi
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo 'BLOCKED: bootstrap поддерживает Linux x86_64; установите стандартный Godot 4.7.2 вручную.' >&2
    exit 1
fi
for tool in curl unzip sha256sum; do
    command -v "$tool" >/dev/null || { echo "BLOCKED: отсутствует $tool." >&2; exit 1; }
done

binary='Godot_v4.7.2-stable_linux.x86_64'
archive="$binary.zip"
url="https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$archive"
# SHA-256 from the official GitHub release asset metadata.
sha256='cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4'
mkdir -p "$project_dir/.tools/godot"
download_dir="$(mktemp -d "$project_dir/.tools/godot/.download.XXXXXX")"
trap 'rm -rf -- "$download_dir"' EXIT
curl --fail --location --retry 2 --connect-timeout 15 --max-time 180 --proto '=https' --tlsv1.2 \
    --output "$download_dir/$archive" "$url"
printf '%s  %s\n' "$sha256" "$download_dir/$archive" | sha256sum --check --status
unzip -q "$download_dir/$archive" -d "$download_dir/extracted"
mkdir -p "$project_dir/.tools/godot/4.7.2"
chmod +x "$download_dir/extracted/$binary"
mv -- "$download_dir/extracted/$binary" "$project_dir/.tools/godot/4.7.2/$binary"
"$project_dir/tools/godot.sh" --version
echo 'PASS: официальная стандартная сборка установлена; SHA-256 проверен.'
