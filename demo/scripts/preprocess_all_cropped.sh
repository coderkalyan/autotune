#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROPPED_DIR="$SCRIPT_DIR/downloaded_songs/cropped"
PREPROCESS="$SCRIPT_DIR/preprocess_song.py"

shopt -s nullglob
# Prefer flac (lossless); fall back to mp3 if no flac exists for same basename.
declare -A seen
for f in "$CROPPED_DIR"/*.flac "$CROPPED_DIR"/*.mp3; do
    name="$(basename "${f%.*}")"
    if [[ -n "${seen[$name]:-}" ]]; then
        continue
    fi
    seen[$name]=1
    echo "=== Processing: $name ==="
    python "$PREPROCESS" "$f" \
        --name "$name" \
        --whisper-model large-v3 \
        --whisper-device cuda
done
