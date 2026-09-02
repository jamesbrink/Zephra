#!/bin/sh
# Capture the frontmost Zephra window to out/zephra-<timestamp>.png (used by agents for visual checks).
set -eu
mkdir -p out
out="out/zephra-$(date +%Y%m%d-%H%M%S).png"
window_id=$(osascript -e 'tell application "System Events" to tell process "Zephra" to get id of first window' 2>/dev/null || true)
if [ -n "$window_id" ]; then
  screencapture -x -o -l "$window_id" "$out"
else
  screencapture -x "$out"
fi
echo "$out"
