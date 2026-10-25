#!/bin/zsh
# Builds Kestirme.app into ./build.
#
#   ./scripts/build.sh          # Apple Silicon build, signed for local use
#   ./scripts/build.sh --run    # same, then (re)launches it from ./build
#   KESTIRME_RELEASE=1 ./scripts/build.sh   # universal binary, hardened runtime + secure timestamp
#
# Never copy local builds over /Applications/Kestirme.app: that copy belongs to Homebrew, and
# Gatekeeper keeps rejecting a replaced bundle folder. Release builds go through scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Kestirme.app
ARCHS=(--arch arm64)
[[ -n "${KESTIRME_RELEASE:-}" ]] && ARCHS+=(--arch x86_64)

swift build -c release "${ARCHS[@]}" 2>&1 | grep -E "error|warning: |Build complete" || true
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Kestirme
[[ -x "$BIN" ]] || { echo "build failed" >&2; exit 1; }

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  mkdir -p build/AppIcon.iconset
  swift scripts/make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kestirme"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Library.json "$APP/Contents/Resources/Library.json"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Select the certificate by its SHA-1: names with non-ASCII letters (Ö) get mangled by `security`.
# A stable identity also keeps the Accessibility permission across rebuilds.
IDENTITY=${KESTIRME_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | awk '{print $2}' || true)}
if [[ -n "$IDENTITY" ]]; then
  STAMP=--timestamp=none
  [[ -n "${KESTIRME_RELEASE:-}" ]] && STAMP=--timestamp
  codesign --force --options runtime $STAMP --sign "$IDENTITY" "$APP"
else
  [[ -z "${KESTIRME_RELEASE:-}" ]] || { echo "No Developer ID Application certificate found." >&2; exit 1; }
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "built: $APP ($(lipo -archs "$APP/Contents/MacOS/Kestirme"))"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x Kestirme 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
