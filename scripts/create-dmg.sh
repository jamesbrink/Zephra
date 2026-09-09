#!/bin/sh
# Package a signed app beside an Applications shortcut in a signed, read-only DMG.
set -eu

APP="${1:?usage: create-dmg.sh <path to .app> <path to .dmg>}"
DMG="${2:?usage: create-dmg.sh <path to .app> <path to .dmg>}"
SCRIPTS=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ICON="$APP/Contents/Resources/AppIcon.icns"
[ -d "$APP" ] || { echo "dmg: no app at $APP"; exit 1; }
[ -f "$ICON" ] || { echo "dmg: app is missing AppIcon.icns"; exit 1; }
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
fi
[ -n "$IDENTITY" ] || { echo "dmg: no Developer ID Application identity in the keychain"; exit 1; }

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/zephra-dmg.XXXXXX")
MOUNTED=0
cleanup() {
    if [ "$MOUNTED" = 1 ] && ! hdiutil detach "$STAGING/volume" -quiet; then
        echo "dmg: could not detach $STAGING/volume; preserving staging" >&2
        return
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$STAGING/content"
ditto "$APP" "$STAGING/content/Zephra.app"
ln -s /Applications "$STAGING/content/Applications"
cp "$ICON" "$STAGING/content/.VolumeIcon.icns"
# hdiutil does not copy the source folder's Finder flags to the volume root.
# Set the custom-icon bit on a writable volume, then seal that volume read-only.
hdiutil create -quiet -volname Zephra -fs HFS+ -format UDRW \
    -srcfolder "$STAGING/content" "$STAGING/Zephra-rw.dmg"
mkdir "$STAGING/volume"
MOUNTED=1
hdiutil attach "$STAGING/Zephra-rw.dmg" -readwrite -nobrowse \
    -mountpoint "$STAGING/volume" -quiet
xcrun SetFile -a C "$STAGING/volume"
hdiutil detach "$STAGING/volume" -quiet
MOUNTED=0
hdiutil convert "$STAGING/Zephra-rw.dmg" -format UDZO \
    -o "$STAGING/Zephra.dmg" -quiet
swift "$SCRIPTS/set-file-icon.swift" "$ICON" "$STAGING/Zephra.dmg"
codesign --force --timestamp --sign "$IDENTITY" "$STAGING/Zephra.dmg"
codesign --verify --strict --verbose=2 "$STAGING/Zephra.dmg"
mkdir -p "$(dirname "$DMG")"
# ditto, not mv: the file icon lives in a resource fork, and a cross-device mv --
# TMPDIR is on the boot volume, build/ need not be -- copies the data fork alone and
# silently drops it. ditto carries forks and Finder flags across volumes.
rm -f "$DMG"
ditto "$STAGING/Zephra.dmg" "$DMG"
rm -f "$STAGING/Zephra.dmg"
xcrun GetFileInfo -a "$DMG" | grep -q C \
    || { echo "dmg: $DMG lost its custom-icon flag on the way to its destination"; exit 1; }
xattr "$DMG" | grep -q com.apple.ResourceFork \
    || { echo "dmg: $DMG lost its icon resource fork on the way to its destination"; exit 1; }
echo "dmg: $DMG"
