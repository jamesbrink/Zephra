#!/bin/sh
# Verify the actual app and installation shortcut in the final mounted installer.
set -eu
DMG="${1:?usage: verify-dmg.sh <path to .dmg> [metadata.json]}"
METADATA="${2:-}"
MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/zephra-dmg-check.XXXXXX")
cleanup() {
    hdiutil detach "$MOUNT" -quiet || true
    rmdir "$MOUNT"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -quiet
[ -d "$MOUNT/Zephra.app" ] || { echo "verify: installer is missing Zephra.app"; exit 1; }
[ -L "$MOUNT/Applications" ] && [ "$(readlink "$MOUNT/Applications")" = /Applications ] \
    || { echo "verify: installer is missing the Applications shortcut"; exit 1; }
[ -f "$MOUNT/.VolumeIcon.icns" ] \
    && cmp -s "$MOUNT/.VolumeIcon.icns" "$MOUNT/Zephra.app/Contents/Resources/AppIcon.icns" \
    || { echo "verify: volume and app icons do not match"; exit 1; }
xcrun GetFileInfo -a "$MOUNT" | grep -q C \
    || { echo "verify: volume custom-icon flag is missing"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$MOUNT/Zephra.app"
xcrun stapler validate "$MOUNT/Zephra.app"
spctl -a -t exec -vv "$MOUNT/Zephra.app"
if [ -n "$METADATA" ]; then
    python3 - "$MOUNT/Zephra.app/Contents/Info.plist" "$METADATA" <<'PYMETA'
import json, plistlib, sys
from pathlib import Path
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
Path(sys.argv[2]).write_text(json.dumps({
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
}) + '\n')
PYMETA
fi
echo "verify: mounted installer app, branding, and Applications shortcut passed"
