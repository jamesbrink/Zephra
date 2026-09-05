#!/bin/sh
# Diffs the vendored ZImageKit sources against upstream mzbac/zimage.swift at the pinned
# commit, and lists every changed hunk that carries no `ZEPHRA-PATCH` marker.
#
# The pinned commit is not in this repository's history, so upstream is fetched into a scratch
# clone (kept between runs under ZIMAGE_SCRATCH, ~/.cache/zephra/zimage-src by default).
#
#   scripts/vendored-diff.sh            # full unified diff, then the unmarked hunks
#   scripts/vendored-diff.sh --check    # only the unmarked hunks; exit 1 when there are any
#
# Files that exist only on our side (new files) are expected to open with a ZEPHRA-PATCH
# comment, and are reported when they do not. VENDORED.md's re-sync procedure runs this after
# hand-applying an upstream diff, so no patch is lost and no stray edit goes unrecorded.
set -eu

UPSTREAM_URL="https://github.com/mzbac/zimage.swift"
UPSTREAM_SHA="970f83e477028e81fc19fc7035228ced89dc1ffd"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OURS="$ROOT/Packages/ZImageKit/Sources/ZImage"
SCRATCH="${ZIMAGE_SCRATCH:-$HOME/.cache/zephra/zimage-src}"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

if [ ! -d "$SCRATCH/.git" ]; then
  mkdir -p "$(dirname "$SCRATCH")"
  git clone -q "$UPSTREAM_URL" "$SCRATCH"
fi
if [ "$(git -C "$SCRATCH" rev-parse HEAD)" != "$UPSTREAM_SHA" ]; then
  git -C "$SCRATCH" fetch -q origin
  git -C "$SCRATCH" checkout -q "$UPSTREAM_SHA"
fi
THEIRS="$SCRATCH/Sources/ZImage"

# The user's shell may alias diff to something else; the system one speaks unified diff.
DIFF=/usr/bin/diff
if [ "$CHECK" = 0 ]; then
  "$DIFF" -ru "$THEIRS" "$OURS" || true
  echo
  echo "== hunks without a ZEPHRA-PATCH marker =="
fi

# Walk the unified diff; a hunk is marked when any of its + or - lines, or the line just
# before the hunk header, mentions ZEPHRA-PATCH. Deletions are reported by their header alone.
status=0
report=$("$DIFF" -ru "$THEIRS" "$OURS" | awk '
  function flush() {
    if (hunk != "" && !marked) { print file ": " hunk; unmarked++ }
    hunk = ""; marked = 0
  }
  /^diff -ru / { flush(); file = $NF; next }
  /^Only in / { next }
  /^\+\+\+ |^--- / { next }
  /^@@ / { flush(); hunk = $0; next }
  hunk != "" && /ZEPHRA-PATCH/ { marked = 1 }
  END { flush(); if (unmarked) exit 1 }
') || status=1
[ -n "$report" ] && echo "$report"

# A file of ours upstream does not have must say why in its first comment block.
for path in $("$DIFF" -rq "$THEIRS" "$OURS" | sed -n 's/^Only in \(.*\): \(.*\)$/\1\/\2/p'); do
  case "$path" in
    "$OURS"/*)
      if ! head -n 12 "$path" | grep -q ZEPHRA-PATCH; then
        echo "${path#"$ROOT"/}: new file without a ZEPHRA-PATCH header"; status=1
      fi ;;
    *) echo "${path#"$SCRATCH"/}: upstream file missing from the vendored tree"; status=1 ;;
  esac
done

if [ "$status" = 0 ]; then echo "every changed hunk is marked"; fi
exit $status
