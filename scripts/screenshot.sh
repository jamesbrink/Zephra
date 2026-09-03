#!/bin/sh
# Capture Zephra's window to out/zephra-<timestamp>.png (used by agents for visual checks).
#
# Captures the window by its CoreGraphics id, which photographs the window itself. Neither of
# the alternatives is safe: a whole-screen grab and a region grab both return whatever is on
# the screen, so an app in front of Zephra ends up in out/ and gets looked at.
#
# Fails rather than falling back, so a missing window says so instead of quietly handing back
# a picture of somebody's desktop.
set -eu
mkdir -p out
out="out/zephra-$(date +%Y%m%d-%H%M%S).png"

window_id=$(swift "$(dirname "$0")/window-id.swift" Zephra 2>/dev/null || true)

if [ -z "$window_id" ]; then
  echo "screenshot: no Zephra window on screen." >&2
  echo "Start the app first (CONFIG=Debug make run), or, if it is running, grant this" >&2
  echo "terminal Screen Recording in System Settings > Privacy & Security." >&2
  exit 1
fi

screencapture -x -o -l "$window_id" "$out"
echo "$out"
