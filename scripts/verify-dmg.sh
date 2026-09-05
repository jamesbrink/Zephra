#!/bin/sh
# Verify the actual app and installation shortcut in the final mounted installer.
set -eu
DMG="${1:?usage: verify-dmg.sh <path to .dmg>}"
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
codesign --verify --deep --strict --verbose=2 "$MOUNT/Zephra.app"
xcrun stapler validate "$MOUNT/Zephra.app"
spctl -a -t exec -vv "$MOUNT/Zephra.app"
echo "verify: mounted installer app and Applications shortcut passed"
