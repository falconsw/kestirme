#!/bin/zsh
# Rebuilds the release binary into build/Kestirme.app and renders panel previews.
# Usage: scripts/dev-render.sh <out-dir> [extra render args…]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; shift
swift build -c release --arch arm64 2>&1 | grep -E "error|Build complete" || true
cp "$(swift build -c release --arch arm64 --show-bin-path)/Kestirme" build/Kestirme.app/Contents/MacOS/Kestirme
cp Resources/Library.json build/Kestirme.app/Contents/Resources/Library.json
B=build/Kestirme.app/Contents/MacOS/Kestirme
$B --render $OUT/hold-light.png "$@"
$B --render $OUT/interactive-dark.png --dark --interactive --query "sekme" "$@"
$B --render $OUT/system-light.png --system --interactive "$@"
$B --render $OUT/hold-dark.png --dark "$@"
