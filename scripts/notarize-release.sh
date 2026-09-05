#!/bin/sh
# Notarize the app first, then ship it inside a separately notarized, stapled DMG.
# API-key variables or NOTARY_PROFILE are consumed by submit-notarization.sh.
set -eu

APP="${1:?usage: notarize-release.sh <path to .app> <path to .zip> <path to .dmg>}"
ZIP="${2:?usage: notarize-release.sh <path to .app> <path to .zip> <path to .dmg>}"
DMG="${3:?usage: notarize-release.sh <path to .app> <path to .zip> <path to .dmg>}"
SCRIPTS=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
[ -d "$APP" ] || { echo "notarize: no bundle at $APP"; exit 1; }

"$SCRIPTS/submit-notarization.sh" "$ZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -t exec -vv "$APP"

# Both distributables contain the app's ticket. The disk image gets its own
# submission and ticket after packaging; rebuilding it afterwards would lose that ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
"$SCRIPTS/create-dmg.sh" "$APP" "$DMG"
"$SCRIPTS/submit-notarization.sh" "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
"$SCRIPTS/verify-dmg.sh" "$DMG"
echo "release: notarized $DMG and $ZIP"
