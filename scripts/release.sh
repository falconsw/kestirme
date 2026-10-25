#!/bin/zsh
# Builds a universal, Developer ID signed and notarized Kestirme DMG for GitHub Releases
# and the Homebrew tap (falconsw/homebrew-tap, Casks/kestirme.rb).
#
#   ./scripts/release.sh                      # uses the "notary" notarytool keychain profile
#   NOTARY_PROFILE=other ./scripts/release.sh
#
# Create a profile once with:
#   xcrun notarytool store-credentials notary --apple-id <email> --team-id <TEAM_ID>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
PROFILE=${NOTARY_PROFILE:-notary}
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | awk '{print $2}' || true)
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate found." >&2; exit 1; }

notarize() {
  local out
  out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)
  echo "$out" | grep -E "id:|status:" | tail -2
  echo "$out" | grep -q "status: Accepted" || { echo "$out" >&2; exit 1; }
}

KESTIRME_RELEASE=1 KESTIRME_SIGN_IDENTITY=$IDENTITY ./scripts/build.sh
APP=build/Kestirme.app

# Staple the app itself too, so a first launch works offline.
ditto -c -k --keepParent "$APP" build/Kestirme-notarize.zip
notarize build/Kestirme-notarize.zip
xcrun stapler staple -q "$APP"

rm -rf build/dmg && mkdir -p build/dmg dist
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
DMG="dist/Kestirme-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Kestirme" -srcfolder build/dmg -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple -q "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "Package: $DMG"
echo "sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
