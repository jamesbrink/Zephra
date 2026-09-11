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
# The export signs manually, with the distribution certificate and the App Store
# profile `scripts/testflight-signing.sh` makes from the same key; it runs first,
# and does nothing when both are already in place. Automatic signing is not an
# option: at export time it asks for a cloud-managed distribution certificate the
# team's key is refused.
#
# This is a TestFlight upload. It is never an App Store submission -- releasing a
# build to the store is a separate act in App Store Connect, and nothing here or
# in ExportOptions-testflight.plist performs it.
set -eu

ARCHIVE="${1:?usage: testflight.sh <archive path> <export path>}"
EXPORT_PATH="${2:?usage: testflight.sh <archive path> <export path>}"
OPTIONS="$(dirname "$0")/ExportOptions-testflight.plist"
SIGNING="$(dirname "$0")/testflight-signing.sh"

[ -d "$ARCHIVE" ] || { echo "testflight: no archive at $ARCHIVE"; exit 1; }
[ -f "$OPTIONS" ] || { echo "testflight: no export options at $OPTIONS"; exit 1; }
[ -x "$SIGNING" ] || { echo "testflight: no signing script at $SIGNING"; exit 1; }

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
    echo "      The key is made in App Store Connect > Users and Access > Integrations;"
    echo "      App Manager is enough, since the export signs with a certificate this"
    echo "      key issues rather than with a cloud-managed one. See"
    echo "      docs/build-and-release.md, TestFlight."
    exit 1
fi
[ -f "$ASC_KEY_PATH" ] || { echo "testflight: no API key at $ASC_KEY_PATH"; exit 1; }

SIGNING_CONFIG="$SIGNING_CONFIG" "$SIGNING"

rm -rf "$EXPORT_PATH"
echo "testflight: uploading $(basename "$ARCHIVE") with key $ASC_KEY_ID"
# /usr/bin first, and this is not fussiness. Packaging the .ipa runs
# /usr/bin/rsync, which is openrsync, and openrsync starts its own server half by
# looking up `rsync` on PATH. On a Mac whose PATH leads with Nix or Homebrew that
# is a different rsync, which rejects openrsync's spelling of its options
# ("--extended-attributes: unknown option") and the export dies as "Copy failed",
# which says nothing about rsync at all.
PATH="/usr/bin:/bin:$PATH" xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "testflight: uploaded. App Store Connect processes the build before it reaches"
echo "            internal testers; internal testing needs no review."
