#!/bin/sh
# Notarizes a signed Zephra.app, staples the ticket to it, and repackages.
#
#   scripts/notarize-release.sh build/Release/Zephra.app build/Zephra.zip
#
# Accepts either an App Store Connect team API key:
#
#   NOTARY_KEY=/path/to/AuthKey_XXXXXXXXXX.p8
#   NOTARY_KEY_ID=XXXXXXXXXX
#   NOTARY_ISSUER_ID=00000000-0000-0000-0000-000000000000
#
# or credentials stored once under the profile named by NOTARY_PROFILE:
#
#   xcrun notarytool store-credentials zephra-notary \
#       --apple-id <apple id> --team-id <team id> --password <app-specific password>
#
# This is the only step that touches the network; `make release` stops before it.
set -eu

APP="${1:?usage: notarize-release.sh <path to .app> <path to .zip>}"
ZIP="${2:?usage: notarize-release.sh <path to .app> <path to .zip>}"
PROFILE="${NOTARY_PROFILE:-zephra-notary}"

[ -d "$APP" ] || { echo "notarize: no bundle at $APP"; exit 1; }
[ -f "$ZIP" ] || { echo "notarize: no archive at $ZIP — run 'make release' first"; exit 1; }

KEY="${NOTARY_KEY:-}"
KEY_ID="${NOTARY_KEY_ID:-}"
ISSUER_ID="${NOTARY_ISSUER_ID:-}"

if [ -n "$KEY$KEY_ID$ISSUER_ID" ]; then
    if [ -z "$KEY" ] || [ -z "$KEY_ID" ] || [ -z "$ISSUER_ID" ]; then
        echo "notarize: NOTARY_KEY, NOTARY_KEY_ID, and NOTARY_ISSUER_ID must be set together"
        exit 1
    fi
    [ -f "$KEY" ] || { echo "notarize: no API key at $KEY"; exit 1; }
    echo "notarize: submitting $ZIP with an App Store Connect API key"
    xcrun notarytool submit "$ZIP" \
        --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER_ID" --wait
else
    echo "notarize: submitting $ZIP as profile '$PROFILE'"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
fi

echo "notarize: stapling the ticket to $APP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# The archive that went to Apple has no ticket in it; rebuild it from the
# stapled bundle so the file that ships works offline on first launch.
echo "notarize: repackaging $ZIP from the stapled bundle"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "verify: spctl -a -t exec -vv"
spctl -a -t exec -vv "$APP"
