#!/bin/sh
# Uploads an already-built iOS archive to TestFlight.
#
#   scripts/testflight.sh build/ZephraMobile.xcarchive build/testflight
#
# `make testflight` builds the archive first and then runs this. The credentials
# are an App Store Connect API key, read from the same signing config `make
# release` sources its Developer ID material from:
#
#   ASC_KEY_PATH    the .p8 file, e.g. ~/Documents/Zephra Signing/AuthKey_XXXX.p8
#   ASC_KEY_ID      the key id App Store Connect shows beside it
#   ASC_ISSUER_ID   the issuer id, one per team
#
# All three together or none: a partial set is a typo rather than a configuration,
# and xcodebuild's own complaint about a missing issuer id says nothing useful.
#
# This is a TestFlight upload. It is never an App Store submission -- releasing a
# build to the store is a separate act in App Store Connect, and nothing here or
# in ExportOptions-testflight.plist performs it.
set -eu

ARCHIVE="${1:?usage: testflight.sh <archive path> <export path>}"
EXPORT_PATH="${2:?usage: testflight.sh <archive path> <export path>}"
OPTIONS="$(dirname "$0")/ExportOptions-testflight.plist"

[ -d "$ARCHIVE" ] || { echo "testflight: no archive at $ARCHIVE"; exit 1; }
[ -f "$OPTIONS" ] || { echo "testflight: no export options at $OPTIONS"; exit 1; }

# Sourced the way signed-build sources it, so a machine can keep its credentials in
# Documents rather than in the environment of whatever shell make was run from.
SIGNING_CONFIG="${SIGNING_CONFIG:-$HOME/Documents/Zephra Signing/signing.env}"
if [ -f "$SIGNING_CONFIG" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$SIGNING_CONFIG"
    set +a
fi

missing=""
for name in ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID; do
    eval "value=\${$name:-}"
    [ -n "$value" ] || missing="$missing $name"
done
if [ -n "$missing" ]; then
    echo "testflight: missing$missing"
    echo "      Set all three in $SIGNING_CONFIG (or in the environment):"
    echo "        ASC_KEY_PATH=\"\$HOME/Documents/Zephra Signing/AuthKey_<key id>.p8\""
    echo "        ASC_KEY_ID=<key id>"
    echo "        ASC_ISSUER_ID=<issuer id>"
    echo "      The key is made in App Store Connect > Users and Access > Integrations,"
    echo "      with the App Manager role. See docs/build-and-release.md, TestFlight."
    exit 1
fi
[ -f "$ASC_KEY_PATH" ] || { echo "testflight: no API key at $ASC_KEY_PATH"; exit 1; }

rm -rf "$EXPORT_PATH"
echo "testflight: uploading $(basename "$ARCHIVE") with key $ASC_KEY_ID"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "testflight: uploaded. App Store Connect processes the build before it reaches"
echo "            internal testers; internal testing needs no review."
