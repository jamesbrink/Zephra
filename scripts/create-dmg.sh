#!/bin/sh
# Package a signed app beside an Applications shortcut in a signed, read-only DMG.
set -eu

APP="${1:?usage: create-dmg.sh <path to .app> <path to .dmg>}"
DMG="${2:?usage: create-dmg.sh <path to .app> <path to .dmg>}"
[ -d "$APP" ] || { echo "dmg: no app at $APP"; exit 1; }
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
fi
[ -n "$IDENTITY" ] || { echo "dmg: no Developer ID Application identity in the keychain"; exit 1; }

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/zephra-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$STAGING/content"
ditto "$APP" "$STAGING/content/Zephra.app"
ln -s /Applications "$STAGING/content/Applications"
hdiutil create -quiet -volname Zephra -fs HFS+ -format UDZO \
    -srcfolder "$STAGING/content" "$STAGING/Zephra.dmg"
codesign --force --timestamp --sign "$IDENTITY" "$STAGING/Zephra.dmg"
codesign --verify --strict --verbose=2 "$STAGING/Zephra.dmg"
mkdir -p "$(dirname "$DMG")"
mv -f "$STAGING/Zephra.dmg" "$DMG"
echo "dmg: $DMG"
