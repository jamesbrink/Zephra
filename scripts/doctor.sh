#!/bin/sh
# Checks the four things a fresh Mac gets wrong before `make build` can work, and prints the fix
# for each rather than leaving the reader to decode a bare "Error 127" from make. Exit status is
# the number of failed checks, so it can gate a script.
set -u
failures=0

fail() {
    failures=$((failures + 1))
    printf 'FAIL  %s\n      fix: %s\n' "$1" "$2"
}
ok() {
    printf 'ok    %s\n' "$1"
}

if command -v xcodegen >/dev/null 2>&1; then
    ok "xcodegen on PATH ($(command -v xcodegen))"
else
    fail "xcodegen is not on PATH; make gen cannot generate the Xcode project" \
        "brew install xcodegen   (or: nix profile install nixpkgs#xcodegen)"
fi

developer_dir=$(xcode-select -p 2>/dev/null || true)
case "$developer_dir" in
    "")
        fail "no active developer directory" \
            "install Xcode.app from the App Store, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        ;;
    /Library/Developer/CommandLineTools*)
        fail "the active developer directory is the Command Line Tools; mlx-swift's Metal kernels need the full Xcode.app" \
            "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        ;;
    *)
        ok "full Xcode selected ($developer_dir)"
        ;;
esac

if xcodebuild -version >/dev/null 2>&1; then
    ok "xcodebuild runs ($(xcodebuild -version 2>/dev/null | head -1))"
else
    fail "xcodebuild does not run; the license is unaccepted or first launch has not completed" \
        "sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
fi

metal=$(xcodebuild -showComponent MetalToolchain 2>/dev/null | awk -F': ' '/^Status/ { print $2 }')
if [ "$metal" = "installed" ]; then
    ok "Metal toolchain installed"
else
    fail "the Metal toolchain is not installed (status: ${metal:-unknown}); Xcode 26 cannot compile MLX's kernels without it" \
        "xcodebuild -downloadComponent MetalToolchain   (about 700 MB, the one setup step that needs the network)"
fi

if command -v hf >/dev/null 2>&1; then
    ok "hf CLI on PATH (optional, for make prefetch)"
else
    printf 'note  hf CLI not on PATH; only make prefetch and make quantize need it: pip install -U huggingface_hub\n'
fi

if [ "$failures" -eq 0 ]; then
    printf 'All checks passed. The first Release build compiles MLX'"'"'s Metal kernels and takes several minutes.\n'
fi
exit "$failures"
