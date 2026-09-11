#!/bin/sh
# What App Store Connect has done with the build `make testflight` just uploaded,
# and what it takes to put that build in front of the internal testers.
#
#   scripts/asc-build-status.sh                 the newest build, once
#   scripts/asc-build-status.sh --watch         every 60 s until it is VALID
#   scripts/asc-build-status.sh attach [id]     add a build to the internal group
#   scripts/asc-build-status.sh detail [id]     what TestFlight makes of a build
#   scripts/asc-build-status.sh compliance [id] answer the export-compliance question
#
# An upload succeeding is not a build reaching a phone: App Store Connect takes
# five to thirty minutes to process one, and only `processingState == VALID` says
# it is installable. This asks, rather than making somebody watch a web page.
#
# The three build subcommands live here rather than in a script of their own
# because all four acts want the same thing, an ES256 token minted from the same
# key, and a second copy of that minting is a second place to get it wrong. A
# build id is optional everywhere: without one they take the newest build, which
# is the one just uploaded.
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
GROUP_ID="${ASC_GROUP_ID:-3ef9f46a-3906-4689-8d11-dbfcd73176cb}"   # the "Internal" beta group
API="https://api.appstoreconnect.apple.com/v1"
COMMAND=status
BUILD_ID=""
WATCH=0
INTERVAL="${ASC_POLL_INTERVAL:-60}"
ATTEMPTS="${ASC_POLL_ATTEMPTS:-40}"  # 40 minutes at the default interval

while [ $# -gt 0 ]; do
    case "$1" in
        --watch) WATCH=1 ;;
        --app) shift; APP_ID="${1:?--app needs an Apple ID}" ;;
        --group) shift; GROUP_ID="${1:?--group needs a beta group id}" ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        status|attach|detail|compliance) COMMAND="$1" ;;
        *) BUILD_ID="$1" ;;
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

# One request, its body left in $WORK/body. A relationship POST answers 204 with
# nothing in it, so the HTTP status decides and an empty body is not a failure.
request() {
    method="$1"; url="$2"; payload="${3:-}"
    umask 077
    printf 'header = "Authorization: Bearer %s"\nsilent\nshow-error\n' "$(mint_token)" > "$WORK/curlrc"
    set -- --config "$WORK/curlrc" -X "$method" -o "$WORK/body" -w '%{http_code}' "$url"
    if [ -n "$payload" ]; then
        set -- "$@" -H "Content-Type: application/json" --data-binary "@$payload"
    fi
    : > "$WORK/body"
    status=$(curl "$@")
    rm -f "$WORK/curlrc"
    if [ -s "$WORK/body" ] && jq -e '.errors' < "$WORK/body" >/dev/null 2>&1; then
        jq -r '.errors[] | "asc-build-status: \(.title): \(.detail // "")"' < "$WORK/body"
        return 1
    fi
    case "$status" in 2??) return 0 ;; esac
    echo "asc-build-status: $method returned HTTP $status"
    return 1
}

fetch() {
    request GET "$API/builds?filter%5Bapp%5D=$APP_ID&sort=-uploadedDate&limit=1&include=preReleaseVersion"
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

# Without an id, whichever build was uploaded last -- the one just sent up.
resolve_build() {
    [ -n "$BUILD_ID" ] && return 0
    fetch || exit 1
    BUILD_ID=$(jq -r '.data[0].id // ""' < "$WORK/body")
    [ -n "$BUILD_ID" ] || { echo "asc-build-status: the app has no builds yet"; exit 1; }
}

# internalBuildState is what a tester's TestFlight shows: READY_FOR_BETA_TESTING
# once it is installable, MISSING_EXPORT_COMPLIANCE while the question is open.
detail() {
    request GET "$API/builds/$BUILD_ID/buildBetaDetail" || exit 1
    jq -r '"build=\($b) internal=\(.data.attributes.internalBuildState) external=\(.data.attributes.externalBuildState)"' \
        --arg b "$BUILD_ID" < "$WORK/body"
}

case "$COMMAND" in
    attach)
        resolve_build
        printf '{"data":[{"type":"builds","id":"%s"}]}' "$BUILD_ID" > "$WORK/attach.json"
        request POST "$API/betaGroups/$GROUP_ID/relationships/builds" "$WORK/attach.json" || exit 1
        echo "asc-build-status: build $BUILD_ID is in beta group $GROUP_ID"
        detail
        exit 0
        ;;
    detail)
        resolve_build; detail; exit 0
        ;;
    # The bundle's ITSAppUsesNonExemptEncryption already answers this, so a build
    # should never need it; it is here for one that was uploaded before the key was.
    compliance)
        resolve_build
        printf '{"data":{"type":"builds","id":"%s","attributes":{"usesNonExemptEncryption":false}}}' \
            "$BUILD_ID" > "$WORK/compliance.json"
        request PATCH "$API/builds/$BUILD_ID" "$WORK/compliance.json" || exit 1
        echo "asc-build-status: build $BUILD_ID declares no non-exempt encryption"
        detail
        exit 0
        ;;
esac

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
