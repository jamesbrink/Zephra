#!/bin/sh
# The distribution certificate and the App Store profile `make testflight` signs
# with, made from the App Store Connect API rather than from Xcode's cloud.
#
#   scripts/testflight-signing.sh
#
# Idempotent: with the identity already in the login keychain and an active
# profile naming it, this does nothing but say so. `scripts/testflight.sh` runs
# it before every export, so the export never has to ask Apple for a certificate
# of its own.
#
# Why by hand at all. Xcode's automatic signing asks App Store Connect for a
# cloud-managed distribution certificate at export time, and the team's key is
# refused it -- "You haven't been given access to cloud-managed distribution
# certificates", a grant only the Account Holder can make. The API key can
# nevertheless *issue* an ordinary distribution certificate, which is the same
# thing without the cloud's custody, so that is what this does: a key and a CSR
# made here, a certificate issued to them, both kept in
# `~/Documents/Zephra Signing/` beside the Developer ID material and imported
# into the login keychain, plus an App Store profile that names the pair.
#
# Apple caps a team at three distribution certificates. This refuses to make a
# fourth and names the three, because revoking one is somebody's decision and
# revoking the wrong one breaks a shipped signing setup elsewhere.
#
# Nothing secret is printed: not the key, not the certificate's private half, not
# the .p12 passphrase, not the API token.
set -eu

BUNDLE_ID="${IOS_BUNDLE_ID:-io.zephra.ZephraMobile}"
PROFILE_NAME="${IOS_PROFILE_NAME:-Zephra iOS App Store}"
CERT_COMMON_NAME="Zephra iOS Distribution"
CERT_EMAIL="brink.james@gmail.com"
WWDR_URL="https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"
OPENSSL=/usr/bin/openssl   # LibreSSL: its PKCS#12 is the one `security import` reads
XCODEBUILD=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild

ASC_TOOL=testflight-signing
# shellcheck disable=SC1091
. "$(dirname "$0")/asc-api.sh"
asc_load_credentials || exit 1
API="$ASC_API/v1"

SIGNING_DIR=$(dirname "$SIGNING_CONFIG")
KEY_FILE="$SIGNING_DIR/ios-distribution.key"
CER_FILE="$SIGNING_DIR/ios-distribution.cer"
P12_FILE="$SIGNING_DIR/ios-distribution.p12"
KEYCHAIN=$(security default-keychain -d user | tr -d ' "')
PROFILE_DIRS="$HOME/Library/MobileDevice/Provisioning Profiles
$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

say() { echo "testflight-signing: $*"; }

# The identity is the certificate *and* its private key: a certificate alone is
# listed by find-certificate and cannot sign anything.
has_identity() {
    security find-identity -v -p codesigning | grep -q "Apple Distribution"
}

# The one exact test for "is this local certificate the one App Store Connect
# holds": its bytes. A serial number has two spellings and this has none.
der_base64() {
    $OPENSSL x509 -inform DER -in "$1" -outform DER 2>/dev/null | $OPENSSL base64 -A
}

list_distribution_certificates() {
    asc_request GET "$API/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=200" || exit 1
}

# The id of the team certificate whose bytes are the local one's, empty if the
# local certificate is not the team's (or there is no local certificate).
matching_certificate_id() {
    [ -f "$CER_FILE" ] || { printf ''; return 0; }
    mine=$(der_base64 "$CER_FILE" | tr -d '\n\r ')
    [ -n "$mine" ] || { printf ''; return 0; }
    jq -r --arg mine "$mine" '
        [.data[] | select((.attributes.certificateContent | gsub("\\s";"")) == $mine) | .id][0] // ""
    ' < "$ASC_WORK/body"
}

create_certificate() {
    list_distribution_certificates
    count=$(jq -r '.data | length' < "$ASC_WORK/body")
    if [ "$count" -ge 3 ]; then
        say "the team already holds $count distribution certificates, Apple's cap:"
        jq -r '.data[] | "      \(.attributes.name // .attributes.certificateType) serial=\(.attributes.serialNumber) expires=\(.attributes.expirationDate)"' \
            < "$ASC_WORK/body"
        say "revoke one in the Developer portal, then run this again. Which one is"
        say "a decision for a person: another machine may be signing with it."
        exit 1
    fi

    say "issuing a distribution certificate ($count of 3 in use)"
    umask 077
    $OPENSSL req -new -newkey rsa:2048 -nodes \
        -keyout "$KEY_FILE" -out "$ASC_WORK/request.csr" \
        -subj "/CN=$CERT_COMMON_NAME/emailAddress=$CERT_EMAIL/C=US" 2>/dev/null
    chmod 600 "$KEY_FILE"

    # Apple takes the PEM; a copy stripped to its base64 body is the other
    # spelling seen in the wild, so it is the retry rather than a second guess.
    sed '1d;$d' "$ASC_WORK/request.csr" | tr -d '\n' > "$ASC_WORK/request.body"
    for form in pem body; do
        case "$form" in
            pem)  jq -n --rawfile csr "$ASC_WORK/request.csr" \
                    '{data:{type:"certificates",attributes:{certificateType:"DISTRIBUTION",csrContent:$csr}}}' \
                    > "$ASC_WORK/create.json" ;;
            body) jq -n --rawfile csr "$ASC_WORK/request.body" \
                    '{data:{type:"certificates",attributes:{certificateType:"DISTRIBUTION",csrContent:$csr}}}' \
                    > "$ASC_WORK/create.json" ;;
        esac
        if asc_request POST "$API/certificates" "$ASC_WORK/create.json"; then
            break
        fi
        [ "$form" = pem ] || { say "App Store Connect refused the certificate request"; exit 1; }
    done

    jq -r '.data.attributes.certificateContent' < "$ASC_WORK/body" | tr -d '\n\r ' \
        | $OPENSSL base64 -d -A -out "$CER_FILE"
    chmod 600 "$CER_FILE"
    $OPENSSL x509 -inform DER -in "$CER_FILE" -noout -subject >/dev/null 2>&1 \
        || { say "what App Store Connect returned is not a DER certificate"; exit 1; }
    CERT_ID=$(jq -r '.data.id' < "$ASC_WORK/body")
    say "certificate $(certificate_line)"
}

certificate_line() {
    name=$($OPENSSL x509 -inform DER -in "$CER_FILE" -noout -subject | sed 's/.*CN *= *//; s/,.*//; s|/.*||')
    serial=$($OPENSSL x509 -inform DER -in "$CER_FILE" -noout -serial | cut -d= -f2)
    until=$($OPENSSL x509 -inform DER -in "$CER_FILE" -noout -enddate | cut -d= -f2)
    printf '"%s" serial=%s expires=%s' "$name" "$serial" "$until"
}

# The passphrase is generated once and kept in the signing config, because the
# .p12 is the backup copy: a Mac that loses its keychain re-imports from it. It
# sets P12_PASS rather than printing, so a second caller cannot mint a second
# passphrase for a file that already has one.
ensure_p12_passphrase() {
    if [ -n "${IOS_DIST_P12_PASSWORD:-}" ]; then
        P12_PASS="$IOS_DIST_P12_PASSWORD"
        return 0
    fi
    P12_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    umask 077
    printf 'IOS_DIST_P12_PASSWORD=%s\n' "$P12_PASS" >> "$SIGNING_CONFIG"
    chmod 600 "$SIGNING_CONFIG"
    IOS_DIST_P12_PASSWORD="$P12_PASS"
}

write_p12() {
    ensure_p12_passphrase
    $OPENSSL x509 -inform DER -in "$CER_FILE" -out "$ASC_WORK/cert.pem"
    umask 077
    $OPENSSL pkcs12 -export -name "$CERT_COMMON_NAME" \
        -inkey "$KEY_FILE" -in "$ASC_WORK/cert.pem" \
        -out "$P12_FILE" -passout "pass:$P12_PASS"
    chmod 600 "$P12_FILE"
}

import_identity() {
    ensure_p12_passphrase
    security import "$P12_FILE" -k "$KEYCHAIN" -P "$P12_PASS" \
        -T /usr/bin/codesign -T /usr/bin/security -T "$XCODEBUILD" >/dev/null 2>&1 \
        || say "the .p12 was already in the keychain, or part of it was"
    has_identity || {
        say "the identity is not in $KEYCHAIN after importing; the key and the"
        say "certificate are at ios-distribution.key and ios-distribution.cer"
        exit 1
    }
}

import_wwdr() {
    if security find-certificate -c "Apple Worldwide Developer Relations" >/dev/null 2>&1; then
        return 0
    fi
    say "importing Apple's WWDR G3 intermediate"
    curl -fsSL "$WWDR_URL" -o "$ASC_WORK/wwdr.cer"
    security import "$ASC_WORK/wwdr.cer" -k "$KEYCHAIN" >/dev/null 2>&1 || true
}

ensure_certificate() {
    import_wwdr
    if has_identity && [ -f "$CER_FILE" ]; then
        list_distribution_certificates
        CERT_ID=$(matching_certificate_id)
        if [ -n "$CERT_ID" ]; then
            say "keychain already holds $(certificate_line)"
            [ -f "$P12_FILE" ] || write_p12
            return 0
        fi
        say "the keychain's Apple Distribution identity is not the team's any more"
    fi
    if [ -f "$KEY_FILE" ] && [ -f "$CER_FILE" ]; then
        list_distribution_certificates
        CERT_ID=$(matching_certificate_id)
        if [ -n "$CERT_ID" ]; then
            say "re-importing the saved certificate $(certificate_line)"
            [ -f "$P12_FILE" ] || write_p12
            import_identity
            return 0
        fi
    fi
    create_certificate
    write_p12
    import_identity
}

bundle_id_record() {
    asc_request GET "$API/bundleIds?filter%5Bidentifier%5D=$BUNDLE_ID" || exit 1
    BUNDLE_RECORD=$(jq -r '.data[0].id // ""' < "$ASC_WORK/body")
    [ -n "$BUNDLE_RECORD" ] || {
        say "no registered bundle id $BUNDLE_ID; register it in the Developer portal"
        exit 1
    }
}

install_profile() {   # $1: base64 profileContent, $2: the profile's name
    printf '%s' "$1" | tr -d '\n\r ' | $OPENSSL base64 -d -A -out "$ASC_WORK/profile.mobileprovision"
    security cms -D -i "$ASC_WORK/profile.mobileprovision" > "$ASC_WORK/profile.plist" 2>/dev/null
    uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$ASC_WORK/profile.plist")
    [ -n "$uuid" ] || { say "the profile has no UUID"; exit 1; }
    # Two homes because Xcode moved the folder and either copy may be the one
    # a given xcodebuild reads.
    echo "$PROFILE_DIRS" | while IFS= read -r dir; do
        mkdir -p "$dir"
        cp "$ASC_WORK/profile.mobileprovision" "$dir/$uuid.mobileprovision"
    done
    say "profile \"$2\" installed as $uuid.mobileprovision"
}

ensure_profile() {
    bundle_id_record
    encoded=$(printf '%s' "$PROFILE_NAME" | jq -sRr @uri)
    asc_request GET "$API/profiles?filter%5Bname%5D=$encoded&include=certificates" || exit 1
    existing=$(jq -r '.data[0].id // ""' < "$ASC_WORK/body")
    if [ -n "$existing" ]; then
        state=$(jq -r '.data[0].attributes.profileState // ""' < "$ASC_WORK/body")
        names_cert=$(jq -r --arg c "$CERT_ID" \
            '[.data[0].relationships.certificates.data[]?.id] | index($c) // "" | tostring' \
            < "$ASC_WORK/body")
        if [ "$state" = ACTIVE ] && [ -n "$names_cert" ] && [ "$names_cert" != "null" ]; then
            install_profile "$(jq -r '.data[0].attributes.profileContent' < "$ASC_WORK/body")" "$PROFILE_NAME"
            return 0
        fi
        say "the existing \"$PROFILE_NAME\" profile is $state and is being replaced"
        asc_request DELETE "$API/profiles/$existing" || exit 1
    fi

    jq -n --arg name "$PROFILE_NAME" --arg bundle "$BUNDLE_RECORD" --arg cert "$CERT_ID" '
        {data:{type:"profiles",
               attributes:{name:$name, profileType:"IOS_APP_STORE"},
               relationships:{bundleId:{data:{type:"bundleIds", id:$bundle}},
                              certificates:{data:[{type:"certificates", id:$cert}]}}}}
    ' > "$ASC_WORK/profile.json"
    asc_request POST "$API/profiles" "$ASC_WORK/profile.json" || exit 1
    install_profile "$(jq -r '.data.attributes.profileContent' < "$ASC_WORK/body")" \
        "$(jq -r '.data.attributes.name' < "$ASC_WORK/body")"
}

ensure_certificate
ensure_profile
say "ready: manual signing with \"Apple Distribution\" and \"$PROFILE_NAME\""
