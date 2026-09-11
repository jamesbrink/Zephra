# Sourced, never run: the one App Store Connect API client the scripts share.
#
#   . "$(dirname "$0")/asc-api.sh"
#   ASC_TOOL=my-script
#   asc_load_credentials
#   asc_request GET "$ASC_API/v1/certificates" && jq . < "$ASC_WORK/body"
#
# There is one copy of the ES256 minting because a second copy is a second place
# to get it wrong: the token is what every one of these acts needs, and the
# signing script wants exactly what the status script already had.
#
# The credentials are an App Store Connect API key, read from the signing config
# `make signed-build` sources:
#
#   ASC_KEY_PATH    the .p8 file, e.g. ~/Documents/Zephra Signing/AuthKey_XXXX.p8
#   ASC_KEY_ID      the key id App Store Connect shows beside it
#   ASC_ISSUER_ID   the issuer id, one per team
#
# The key is never printed and the minted token never reaches a command line: it
# is handed to curl through a config file in a private temporary directory, so it
# is not in `ps` output for the length of the request.

ASC_API="https://api.appstoreconnect.apple.com"
ASC_TOOL="${ASC_TOOL:-asc}"

# Reads the signing config, refuses a partial key by name, and opens the private
# working directory the token and every response body live in.
#
# The environment wins over the file. A Mac keeps the three in
# `~/Documents/Zephra Signing/signing.env`; CI has no such file (it runs with
# SIGNING_CONFIG=/dev/null, which is not a regular file and so is not sourced)
# and hands them in from repository secrets instead. Sourcing as it stands would
# put a file's copy over a variable somebody deliberately exported, so whatever
# was already set is put back afterwards.
asc_load_credentials() {
    SIGNING_CONFIG="${SIGNING_CONFIG:-$HOME/Documents/Zephra Signing/signing.env}"
    asc_given_key_path="${ASC_KEY_PATH:-}"
    asc_given_key_id="${ASC_KEY_ID:-}"
    asc_given_issuer_id="${ASC_ISSUER_ID:-}"
    if [ -f "$SIGNING_CONFIG" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$SIGNING_CONFIG"
        set +a
    fi
    if [ -n "$asc_given_key_path" ]; then ASC_KEY_PATH="$asc_given_key_path"; fi
    if [ -n "$asc_given_key_id" ]; then ASC_KEY_ID="$asc_given_key_id"; fi
    if [ -n "$asc_given_issuer_id" ]; then ASC_ISSUER_ID="$asc_given_issuer_id"; fi
    export ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID

    missing=""
    for name in ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID; do
        eval "value=\${$name:-}"
        [ -n "$value" ] || missing="$missing $name"
    done
    if [ -n "$missing" ]; then
        echo "$ASC_TOOL: missing$missing"
        echo "      Set all three in $SIGNING_CONFIG; see docs/build-and-release.md, TestFlight."
        return 1
    fi
    [ -f "$ASC_KEY_PATH" ] || { echo "$ASC_TOOL: no API key at $ASC_KEY_PATH"; return 1; }
    command -v jq >/dev/null || { echo "$ASC_TOOL: jq is not on PATH"; return 1; }

    ASC_WORK=$(mktemp -d); chmod 700 "$ASC_WORK"
    trap 'rm -rf "$ASC_WORK"' EXIT INT TERM
}

asc_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# ES256, by hand: openssl signs to DER, and a JWT wants the two integers raw and
# fixed width, so each is trimmed of its sign byte or left-padded to 32 bytes.
asc_pad64() {
    h="$1"
    while [ ${#h} -gt 64 ]; do h=${h#??}; done
    while [ ${#h} -lt 64 ]; do h="0$h"; done
    printf '%s' "$h"
}

asc_mint_token() {
    now=$(date +%s)
    header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | asc_b64url)
    payload=$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
        "$ASC_ISSUER_ID" "$now" "$((now + 1200))" | asc_b64url)
    printf '%s.%s' "$header" "$payload" > "$ASC_WORK/input"
    openssl dgst -sha256 -sign "$ASC_KEY_PATH" -out "$ASC_WORK/sig.der" "$ASC_WORK/input"
    r=$(openssl asn1parse -inform DER -in "$ASC_WORK/sig.der" | awk -F: '/INTEGER/ {print $4}' | sed -n 1p)
    s=$(openssl asn1parse -inform DER -in "$ASC_WORK/sig.der" | awk -F: '/INTEGER/ {print $4}' | sed -n 2p)
    sig=$(printf '%s%s' "$(asc_pad64 "$r")" "$(asc_pad64 "$s")" | xxd -r -p | asc_b64url)
    printf '%s.%s' "$(cat "$ASC_WORK/input")" "$sig"
}

# One request, its body left in $ASC_WORK/body. A relationship POST answers 204
# with nothing in it, so the HTTP status decides and an empty body is not a
# failure. The errors Apple returns are printed and the call fails.
asc_request() {
    method="$1"; url="$2"; payload="${3:-}"
    umask 077
    printf 'header = "Authorization: Bearer %s"\nsilent\nshow-error\n' "$(asc_mint_token)" > "$ASC_WORK/curlrc"
    set -- --config "$ASC_WORK/curlrc" -X "$method" -o "$ASC_WORK/body" -w '%{http_code}' "$url"
    if [ -n "$payload" ]; then
        set -- "$@" -H "Content-Type: application/json" --data-binary "@$payload"
    fi
    : > "$ASC_WORK/body"
    status=$(curl "$@")
    rm -f "$ASC_WORK/curlrc"
    if [ -s "$ASC_WORK/body" ] && jq -e '.errors' < "$ASC_WORK/body" >/dev/null 2>&1; then
        jq -r --arg tool "$ASC_TOOL" '.errors[] | "\($tool): \(.title): \(.detail // "")"' < "$ASC_WORK/body"
        return 1
    fi
    case "$status" in 2??) return 0 ;; esac
    echo "$ASC_TOOL: $method returned HTTP $status"
    return 1
}
