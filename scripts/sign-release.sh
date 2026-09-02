#!/bin/sh
# Signs a built Zephra.app for distribution and verifies the result.
#
#   scripts/sign-release.sh build/Release/Zephra.app
#
# SIGN_IDENTITY names the certificate; left empty, the first "Developer ID
# Application" identity in the keychain is used. The build itself signs ad-hoc
# (project.yml sets CODE_SIGN_IDENTITY to "-"), so `make build` keeps working on
# a machine with no certificate at all, and this script re-signs on top of that.
set -eu

APP="${1:?usage: sign-release.sh <path to .app>}"
[ -d "$APP" ] || { echo "sign: no bundle at $APP"; exit 1; }

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
fi
if [ -z "$IDENTITY" ]; then
    echo "sign: no Developer ID Application identity in the keychain."
    echo "      Install one, or pass SIGN_IDENTITY=... to make."
    exit 1
fi
echo "sign: $IDENTITY"

FLAGS="--force --timestamp --options runtime --generate-entitlement-der"
if [ -n "${SIGN_ENTITLEMENTS:-}" ]; then
    FLAGS="$FLAGS --entitlements $SIGN_ENTITLEMENTS"
fi

# Nested code first, outermost last: a signature seals what is inside it, so
# anything signed after the app would invalidate the app's own seal. The bundle
# carries two resource bundles (mlx-swift's default.metallib and
# swift-transformers' tokenizer configs) and no frameworks today; the find below
# covers frameworks and loose dylibs too, so a new dependency needs no edit here.
# --deep is deliberately not used for signing: it is deprecated, and walking the
# bundle ourselves means every nested item gets the same hardened-runtime flags.
find "$APP/Contents" -depth \
    \( -type d \( -name '*.framework' -o -name '*.bundle' -o -name '*.xpc' -o -name '*.appex' \) \
    -o -type f \( -name '*.dylib' -o -name '*.so' \) \) -print \
    | while IFS= read -r item; do
        echo "sign:   $(basename "$item")"
        # shellcheck disable=SC2086
        codesign $FLAGS --sign "$IDENTITY" "$item"
    done

# shellcheck disable=SC2086
codesign $FLAGS --sign "$IDENTITY" "$APP"

echo "verify: codesign --verify --deep --strict"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "verify: spctl -a -t exec -vv"
if spctl -a -t exec -vv "$APP" 2>&1 | tee /dev/stderr | grep -q 'accepted'; then
    :
else
    echo "verify: Gatekeeper rejects the app because it is not notarized yet."
    echo "        That is expected here — run 'make notarize' next."
fi
