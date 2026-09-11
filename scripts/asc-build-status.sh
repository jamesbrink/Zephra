#!/bin/sh
# What App Store Connect has done with the build `make testflight` just uploaded.
#
#   scripts/asc-build-status.sh            the newest build, once
#   scripts/asc-build-status.sh --watch    every 60 s until it is VALID
#
# An upload succeeding is not a build reaching a phone: App Store Connect takes
# five to thirty minutes to process one, and only `processingState == VALID` says
# it is installable. This asks, rather than making somebody watch a web page.
#
# The credentials are the same App Store Connect API key the upload uses, read
# from the same signing config:
#
#   ASC_KEY_PATH    the .p8 file, e.g. ~/Documents/Zephra Signing/AuthKey_XXXX.p8
#   ASC_KEY_ID      the key id App Store Connect shows beside it
#   ASC_ISSUER_ID   the issuer id, one per team
#
# The key is never printed and the minted token never reaches a command line: it
# is handed to curl through a config file in a private temporary directory, so it
# is not in `ps` output for the length of the request.
set -eu

APP_ID="${ASC_APP_ID:-6811136175}"   # Zephra Companion
API="https://api.appstoreconnect.apple.com/v1"
WATCH=0
INTERVAL="${ASC_POLL_INTERVAL:-60}"
ATTEMPTS="${ASC_POLL_ATTEMPTS:-40}"  # 40 minutes at the default interval

while [ $# -gt 0 ]; do
    case "$1" in
        --watch) WATCH=1 ;;
        --app) shift; APP_ID="${1:?--app needs an Apple ID}" ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "asc-build-status: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done

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
    echo "asc-build-status: missing$missing"
    echo "      Set all three in $SIGNING_CONFIG; see docs/build-and-release.md, TestFlight."
    exit 1
fi
[ -f "$ASC_KEY_PATH" ] || { echo "asc-build-status: no API key at $ASC_KEY_PATH"; exit 1; }
command -v jq >/dev/null || { echo "asc-build-status: jq is not on PATH"; exit 1; }

WORK=$(mktemp -d); chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT INT TERM

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# ES256, by hand: openssl signs to DER, and a JWT wants the two integers raw and
# fixed width, so each is trimmed of its sign byte or left-padded to 32 bytes.
pad64() {
    h="$1"
    while [ ${#h} -gt 64 ]; do h=${h#??}; done
    while [ ${#h} -lt 64 ]; do h="0$h"; done
    printf '%s' "$h"
}

mint_token() {
    now=$(date +%s)
    header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64url)
    payload=$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
        "$ASC_ISSUER_ID" "$now" "$((now + 1200))" | b64url)
    printf '%s.%s' "$header" "$payload" > "$WORK/input"
    openssl dgst -sha256 -sign "$ASC_KEY_PATH" -out "$WORK/sig.der" "$WORK/input"
    r=$(openssl asn1parse -inform DER -in "$WORK/sig.der" | awk -F: '/INTEGER/ {print $4}' | sed -n 1p)
    s=$(openssl asn1parse -inform DER -in "$WORK/sig.der" | awk -F: '/INTEGER/ {print $4}' | sed -n 2p)
    sig=$(printf '%s%s' "$(pad64 "$r")" "$(pad64 "$s")" | xxd -r -p | b64url)
    printf '%s.%s' "$(cat "$WORK/input")" "$sig"
}

fetch() {
    umask 077
    printf 'header = "Authorization: Bearer %s"\nsilent\nshow-error\n' "$(mint_token)" > "$WORK/curlrc"
    curl --config "$WORK/curlrc" \
        "$API/builds?filter%5Bapp%5D=$APP_ID&sort=-uploadedDate&limit=1&include=preReleaseVersion" \
        > "$WORK/body"
    rm -f "$WORK/curlrc"
    if jq -e '.errors' < "$WORK/body" >/dev/null 2>&1; then
        jq -r '.errors[] | "asc-build-status: \(.title): \(.detail // "")"' < "$WORK/body"
        return 1
    fi
}

report() {
    jq -r '
      if (.data | length) == 0 then "asc-build-status: the app has no builds yet"
      else
        (.data[0]) as $b
        | ((.included // [])[0].attributes.version // "?") as $v
        | "version=\($v) build=\($b.attributes.version) state=\($b.attributes.processingState) id=\($b.id) uploaded=\($b.attributes.uploadedDate)"
      end' < "$WORK/body"
}

state() { jq -r '.data[0].attributes.processingState // "NONE"' < "$WORK/body"; }

attempt=1
while :; do
    fetch || exit 1
    report
    [ "$WATCH" -eq 1 ] || break
    case "$(state)" in
        VALID) exit 0 ;;
        FAILED|INVALID) echo "asc-build-status: processing did not succeed"; exit 1 ;;
    esac
    if [ "$attempt" -ge "$ATTEMPTS" ]; then
        echo "asc-build-status: still not VALID after $attempt checks"
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep "$INTERVAL"
done
