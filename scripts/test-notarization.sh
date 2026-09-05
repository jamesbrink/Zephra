#!/bin/sh
# Exercise verdict handling without credentials or network access.
set -eu
SCRIPTS=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zephra-notary-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$TEST_DIR/bin"
touch "$TEST_DIR/app.zip" "$TEST_DIR/test-key.p8"
cat >"$TEST_DIR/bin/xcrun" <<'STUB'
#!/bin/sh
[ "${TEST_NOTARY_STATUS:-}" != ToolFailure ] || exit 42
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>id</key><string>test-submission</string>
<key>status</key><string>$TEST_NOTARY_STATUS</string>
</dict></plist>
PLIST
STUB
chmod +x "$TEST_DIR/bin/xcrun"
PATH="$TEST_DIR/bin:$PATH"
export PATH
unset NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER_ID
NOTARY_PROFILE=test-only
export NOTARY_PROFILE
for verdict in Accepted Invalid Rejected ToolFailure; do
    TEST_NOTARY_STATUS=$verdict
    export TEST_NOTARY_STATUS
    result=0
    "$SCRIPTS/submit-notarization.sh" "$TEST_DIR/app.zip" >"$TEST_DIR/output" 2>&1 || result=$?
    if [ "$verdict" = Accepted ]; then
        [ "$result" = 0 ] || { cat "$TEST_DIR/output"; exit 1; }
    else
        [ "$result" != 0 ] || { echo "test: incorrectly accepted $verdict"; exit 1; }
    fi
done
TEST_NOTARY_STATUS=Accepted
NOTARY_KEY="$TEST_DIR/test-key.p8"
export TEST_NOTARY_STATUS NOTARY_KEY
if "$SCRIPTS/submit-notarization.sh" "$TEST_DIR/app.zip" >"$TEST_DIR/output" 2>&1; then
    echo "test: partial credentials must fail"
    exit 1
fi
NOTARY_KEY_ID=test-only
NOTARY_ISSUER_ID=test-only
export NOTARY_KEY_ID NOTARY_ISSUER_ID
"$SCRIPTS/submit-notarization.sh" "$TEST_DIR/app.zip"
echo "test: Accepted, rejection, command failure, and credential validation passed"
