#!/bin/sh
# Submit an app archive or disk image and require Apple's Accepted verdict.
# Credentials come from the environment, never from repository files.
set -eu

ARCHIVE="${1:?usage: submit-notarization.sh <path to archive>}"
[ -f "$ARCHIVE" ] || { echo "notarize: no archive at $ARCHIVE"; exit 1; }
PROFILE="${NOTARY_PROFILE:-zephra-notary}"
KEY="${NOTARY_KEY:-}"
KEY_ID="${NOTARY_KEY_ID:-}"
ISSUER_ID="${NOTARY_ISSUER_ID:-}"
RESULT=$(mktemp "${TMPDIR:-/tmp}/zephra-notary.XXXXXX")
trap 'rm -f "$RESULT"' EXIT
trap 'exit 1' HUP INT TERM

echo "notarize: submitting $ARCHIVE and waiting for Apple"
if [ -n "$KEY$KEY_ID$ISSUER_ID" ]; then
    if [ -z "$KEY" ] || [ -z "$KEY_ID" ] || [ -z "$ISSUER_ID" ]; then
        echo "notarize: NOTARY_KEY, NOTARY_KEY_ID, and NOTARY_ISSUER_ID must be set together"
        exit 1
    fi
    [ -f "$KEY" ] || { echo "notarize: no API key at the configured path"; exit 1; }
    xcrun notarytool submit "$ARCHIVE" --key "$KEY" --key-id "$KEY_ID" \
        --issuer "$ISSUER_ID" --wait --output-format plist >"$RESULT"
else
    xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" \
        --wait --output-format plist >"$RESULT"
fi
STATUS=$(/usr/libexec/PlistBuddy -c 'Print :status' "$RESULT")
SUBMISSION=$(/usr/libexec/PlistBuddy -c 'Print :id' "$RESULT")
echo "notarize: $STATUS ($SUBMISSION)"
[ "$STATUS" = Accepted ] || { echo "notarize: Apple did not accept this submission"; exit 1; }
