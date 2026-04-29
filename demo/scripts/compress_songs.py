#!/usr/bin/env python3
"""Compress FLACs in downloaded_songs/ to MP3 in downloaded_songs/compressed/."""

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SRC_DIR = SCRIPT_DIR / "downloaded_songs"
DST_DIR = SRC_DIR / "compressed"
BITRATE = "192k"


def main() -> int:
    if not SRC_DIR.is_dir():
        print(f"missing source dir: {SRC_DIR}", file=sys.stderr)
        return 1

    DST_DIR.mkdir(exist_ok=True)

    flacs = sorted(SRC_DIR.glob("*.flac"))
    if not flacs:
        print("no flacs found")
        return 0

    fail = 0
    for src in flacs:
        dst = DST_DIR / (src.stem + ".mp3")
        if dst.exists():
            print(f"skip {src.name} (exists)")
            continue
        print(f"encode {src.name} -> {dst.name}")
        cmd = [
            "ffmpeg",
            "-y",
            "-loglevel", "error",
            "-i", str(src),
            "-codec:a", "libmp3lame",
            "-b:a", BITRATE,
            "-map_metadata", "0",
            "-id3v2_version", "3",
            str(dst),
        ]
        res = subprocess.run(cmd)
        if res.returncode != 0:
            print(f"  failed: {src.name}", file=sys.stderr)
            fail += 1

    print(f"done. {len(flacs) - fail}/{len(flacs)} ok")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
