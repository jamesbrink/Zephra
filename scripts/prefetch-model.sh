#!/bin/sh
# Download the default model weights into the Hugging Face cache so first launch skips the 13 GB download.
set -eu
model="${1:-mzbac/Z-Image-Turbo-8bit}"
hf download "$model" --exclude "assets/*"
