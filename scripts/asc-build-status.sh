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
# The four build subcommands live here rather than in scripts of their own
# because they are one conversation about one build. The token they all need is
# minted by `scripts/asc-api.sh`, which `scripts/testflight-signing.sh` uses too.
# A build id is optional everywhere: without one they take the newest build,
# which is the one just uploaded.
set -eu

APP_ID="${ASC_APP_ID:-6811136175}"   # Zephra Companion
GROUP_ID="${ASC_GROUP_ID:-3ef9f46a-3906-4689-8d11-dbfcd73176cb}"   # the "Internal" beta group
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

ASC_TOOL=asc-build-status
# shellcheck disable=SC1091
. "$(dirname "$0")/asc-api.sh"
asc_load_credentials || exit 1
API="$ASC_API/v1"
WORK="$ASC_WORK"
request() { asc_request "$@"; }

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
