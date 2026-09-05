#!/bin/sh
# Capture Zephra's window to out/zephra-<timestamp>.png (used by agents for visual checks).
#
# Captures the window by its CoreGraphics id, which photographs the window itself. Neither of
# the alternatives is safe: a whole-screen grab and a region grab both return whatever is on
# the screen, so an app in front of Zephra ends up in out/ and gets looked at.
#
# WINDOW=<title> names a window by its title instead of taking the largest one: the Settings
# window is titled after its tab, so `make screenshot WINDOW=General` photographs that tab
# while the main window stays where it is. The file is then out/zephra-<title>-<timestamp>.png.
#
# Fails rather than falling back, so a missing window says so instead of quietly handing back
# a picture of somebody's desktop.
set -eu
mkdir -p out
stamp=$(date +%Y%m%d-%H%M%S)
title="${WINDOW:-}"

if [ -n "$title" ]; then
  out="out/zephra-$(printf '%s' "$title" | tr -c 'A-Za-z0-9' '-')-$stamp.png"
  window_id=$(swift "$(dirname "$0")/window-id.swift" Zephra "$title" 2>/dev/null || true)
else
  out="out/zephra-$stamp.png"
  window_id=$(swift "$(dirname "$0")/window-id.swift" Zephra 2>/dev/null || true)
fi

if [ -z "$window_id" ]; then
  if [ -n "$title" ]; then
    echo "screenshot: no Zephra window titled \"$title\" on screen." >&2
  else
    echo "screenshot: no Zephra window on screen." >&2
  fi
  echo "Start the app first (CONFIG=Debug make run), or, if it is running, grant this" >&2
  echo "terminal Screen Recording in System Settings > Privacy & Security." >&2
  exit 1
fi

screencapture -x -o -l "$window_id" "$out"
echo "$out"
