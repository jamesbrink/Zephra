#!/usr/bin/env bash
# Renders the picture each model shows on its card in the first-launch chooser.
#
# One prompt at one seed for every model, so a row of cards compares the models and not the
# prompts. The output is 800x450 JPEG, the card's 16:9 at roughly @2x, written straight into
# the asset catalog's image sets.
#
# The models have to be on this Mac already: point --models at a folder holding the packed
# variants (what `make mirror` writes, or the app's own models folder). A model that is not
# there is skipped with a line, and its card falls back to a plain panel until it is made.
#
# Skipped, not fetched. `ZephraBench` downloads what it cannot find — that is the right
# behaviour for a benchmark and the wrong one here, where a missing variant would quietly pull
# tens of gigabytes and then build them. `ALLOW_DOWNLOAD=1` asks for that on purpose.
#
#   scripts/make-samples.sh [MODELS_DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="${1:-${MODELS_DIR:-$HOME/Library/Application Support/Zephra/Models}}"
BENCH="$ROOT/build/Release/ZephraBench"
ASSETS="$ROOT/Sources/Zephra/Resources/Assets.xcassets"
WORK="$ROOT/build/samples"

# The website's own picture, so the app and the site show the same hand.
PROMPT="Editorial still life photograph of a tiny sculptural copper robot reading a folded newspaper on a warm ivory stone bench, a single olive branch casting delicate shadows, late afternoon amber sunlight, charcoal background, tactile brushed metal, quiet playful character, refined art direction, beautiful realistic materials, spacious composition, no legible text, no watermark"
SEED=42

# model id, the size to render at (each family's own preset nearest 16:9), and the release
# folder under Downloads/ that would hold its weights when it is not a locally packed variant.
MODELS_AND_SIZES=(
  "flux2-klein-4b-4bit 1344x768 black-forest-labs--FLUX.2-klein-4B"
  "flux2-klein-4b-8bit 1344x768 black-forest-labs--FLUX.2-klein-4B"
  "z-image-turbo-8bit 1344x768 mzbac--Z-Image-Turbo-8bit"
  "z-image-turbo-4bit 1344x768 Tongyi-MAI--Z-Image-Turbo"
  "wan-2.2-ti2v-5b-4bit 832x480 FastVideo--FastWan2.2-TI2V-5B-FullAttn-Diffusers"
  "ltx-2.5-distilled-4bit 768x512 mlx-community--ltx-2.5-mlx"
  "ltx-2.5-distilled-audio-4bit 768x512 mlx-community--ltx-2.5-mlx"
)

[ -x "$BENCH" ] || { echo "build ZephraBench first: make bench ARGS=--help"; exit 1; }
mkdir -p "$WORK"

for entry in "${MODELS_AND_SIZES[@]}"; do
  set -- $entry
  id="$1"; size="$2"; repo="$3"
  out="$WORK/$id.png"
  if [ ! -f "$out" ]; then
    if [ ! -d "$MODELS/$id" ] && [ ! -d "$MODELS/Downloads/$repo" ] \
       && [ "${ALLOW_DOWNLOAD:-0}" != "1" ]; then
      echo "-- skipped $id: no weights under $MODELS (ALLOW_DOWNLOAD=1 to fetch them)"
      continue
    fi
    echo "== $id at $size"
    # A clip model's poster is written beside the MP4 and is what the card shows. Wan's first
    # frame reads better at a second than at nine frames; LTX's does not change.
    frames=""
    case "$id" in *ltx*) frames="--frames 9" ;; *wan*) frames="--frames 25" ;; esac
    "$BENCH" --models "$MODELS" --model "$id" --size "$size" --runs 1 \
      --prompt "$PROMPT" --out "$out" $frames || { echo "-- skipped $id"; continue; }
  fi
  set +e
  dir="$ASSETS/Sample-$id.imageset"
  mkdir -p "$dir"
  # Fill 800x450 keeping the shape, then centre-crop: every card is the same rectangle.
  sips -s format jpeg -s formatOptions 78 -Z 1600 "$out" --out "$WORK/$id.jpg" >/dev/null
  python3 "$ROOT/scripts/crop-sample.py" "$WORK/$id.jpg" "$dir/sample.jpg"
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "sample.jpg",
      "idiom" : "universal",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  set -e
  echo "-- wrote $dir"
done
