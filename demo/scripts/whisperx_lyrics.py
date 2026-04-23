#!/usr/bin/env python3
"""
whisperx_lyrics.py — Generate word-level synced lyrics using WhisperX.

Runs Whisper transcription + forced alignment on a song's vocals.wav to
produce per-word timestamps, saved as lyrics.json in the song directory.

Requires: pip install "whisperx @ git+https://github.com/m-bain/whisperX.git"
(Python 3.10–3.13 only — NOT compatible with Python 3.14+)

Usage:
  python whisperx_lyrics.py songs/sunflower_spider_man_into_the_spider_verse
  python whisperx_lyrics.py songs/espresso --model large-v2
  python whisperx_lyrics.py songs/espresso --overwrite
"""

import argparse
import json
import sys
from pathlib import Path


def run(song_dir: Path, model_name: str, device: str, overwrite: bool) -> None:
    import whisperx

    vocals_path = song_dir / "vocals.wav"
    if not vocals_path.exists():
        sys.exit(f"Error: vocals.wav not found in {song_dir}")

    lyrics_path = song_dir / "lyrics.json"
    if lyrics_path.exists() and not overwrite:
        sys.exit(f"lyrics.json already exists — use --overwrite to replace")

    print(f"Loading Whisper model '{model_name}' on {device} ...")
    model = whisperx.load_model(model_name, device=device, compute_type="int8")

    print(f"Loading audio: {vocals_path}")
    audio = whisperx.load_audio(str(vocals_path))

    print("Transcribing ...")
    result = model.transcribe(audio, batch_size=8)

    print("Aligning (forced word-level) ...")
    align_model, metadata = whisperx.load_align_model(language_code="en", device=device)
    result = whisperx.align(result["segments"], align_model, metadata, audio, device=device)

    segments = []
    for seg in result["segments"]:
        words_raw = seg.get("words", [])
        if not words_raw:
            continue
        words = []
        for w in words_raw:
            start = w.get("start")
            end = w.get("end")
            if start is None:
                continue
            words.append({
                "timestamp_ms": round(start * 1000),
                "end_ms": round(end * 1000) if end is not None else None,
                "text": w["word"].strip(),
            })
        if not words:
            continue
        seg_text = " ".join(w["text"] for w in words)
        segments.append({
            "timestamp_ms": words[0]["timestamp_ms"],
            "text": seg_text,
            "words": words,
        })

    lyrics_path.write_text(json.dumps(segments, indent=2) + "\n")
    total_words = sum(len(s["words"]) for s in segments)
    print(f"Done: {len(segments)} lines, {total_words} words → {lyrics_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate word-level lyrics with WhisperX.")
    parser.add_argument("song_dir", type=Path, help="Song directory (must contain vocals.wav)")
    parser.add_argument("--model", default="base", help="Whisper model size (default: base)")
    parser.add_argument("--device", default="cpu", help="Device: cpu or cuda (default: cpu)")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing lyrics.json")
    args = parser.parse_args()

    run(args.song_dir.resolve(), args.model, args.device, args.overwrite)


if __name__ == "__main__":
    main()
