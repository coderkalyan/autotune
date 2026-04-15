#!/usr/bin/env python3
"""
Crop an MP3 and save the result to a sibling 'cropped/' folder,
leaving the original untouched. All ID3 metadata is preserved.

Fades are applied automatically:
  - Fade IN  if start > 0 (cutting into the middle of the song)
  - Fade OUT if end < total song duration (cutting before the natural end)

Usage:
    python3 crop_song.py <file.mp3> <start> <end> [fade_duration]

Times: seconds (90), MM:SS (1:30), or HH:MM:SS (0:01:30).
fade_duration: seconds for each fade (default: 2)
Output: <parent_dir>/cropped/<filename>.mp3
"""

import sys
import os
import subprocess
import tempfile
from mutagen.id3 import ID3, ID3NoHeaderError, TXXX

FADE_DURATION = 2  # seconds, used when a fade is needed


def parse_seconds(t: str) -> float:
    """Convert MM:SS, HH:MM:SS, or bare seconds string to a float in seconds."""
    parts = t.split(":")
    if len(parts) == 1:
        return float(parts[0])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + float(parts[1])
    else:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])


def get_duration(path: str) -> float:
    """Return the total duration of an audio file in seconds via ffprobe."""
    result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path,
        ],
        capture_output=True, text=True,
    )
    return float(result.stdout.strip())


def main():
    if len(sys.argv) not in (4, 5):
        print("Usage: crop_song.py <file.mp3> <start> <end> [fade_duration]")
        print("  Times: seconds (90) or MM:SS (1:30) or HH:MM:SS (0:01:30)")
        sys.exit(1)

    src = sys.argv[1]
    start_str = sys.argv[2]
    end_str = sys.argv[3]
    fade_dur = float(sys.argv[4]) if len(sys.argv) == 5 else FADE_DURATION

    if not os.path.isfile(src):
        print(f"Error: file not found: {src}")
        sys.exit(1)

    src_abs = os.path.abspath(src)
    src_dir = os.path.dirname(src_abs)
    filename = os.path.basename(src_abs)

    start_sec = parse_seconds(start_str)
    end_sec   = parse_seconds(end_str)
    total_dur = get_duration(src_abs)

    need_fade_in  = start_sec > 0
    need_fade_out = (total_dur - end_sec) > 0.5  # 0.5s tolerance for rounding

    clip_dur = end_sec - start_sec

    cropped_dir = os.path.join(src_dir, "cropped")
    os.makedirs(cropped_dir, exist_ok=True)
    dest = os.path.join(cropped_dir, filename)

    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".mp3", dir=cropped_dir)
    os.close(tmp_fd)

    try:
        if need_fade_in or need_fade_out:
            # Build afade filter chain
            filters = []
            if need_fade_in:
                filters.append(f"afade=t=in:st=0:d={fade_dur}")
            if need_fade_out:
                fade_out_start = clip_dur - fade_dur
                filters.append(f"afade=t=out:st={fade_out_start:.3f}:d={fade_dur}")

            af = ",".join(filters)

            cmd = [
                "ffmpeg", "-y",
                "-i", src_abs,
                "-ss", start_str,
                "-to", end_str,
                "-af", af,
                "-c:a", "libmp3lame", "-q:a", "0",  # highest quality VBR re-encode
                "-map_metadata", "0",
                tmp_path,
            ]
        else:
            # No fades — stream-copy, no re-encode
            cmd = [
                "ffmpeg", "-y",
                "-i", src_abs,
                "-ss", start_str,
                "-to", end_str,
                "-c", "copy",
                "-map_metadata", "0",
                tmp_path,
            ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print("ffmpeg error:")
            print(result.stderr)
            os.unlink(tmp_path)
            sys.exit(1)

        os.replace(tmp_path, dest)

        # ffmpeg drops APIC (album art) during re-encode — copy it from source.
        # Also embed crop timestamps for future lyric sync.
        try:
            src_tags = ID3(src_abs)
            dest_tags = ID3(dest)

            # Restore album art if re-encoded (ffmpeg drops APIC)
            if need_fade_in or need_fade_out:
                apic_frames = src_tags.getall("APIC")
                if apic_frames:
                    dest_tags.delall("APIC")
                    for frame in apic_frames:
                        dest_tags.add(frame)

            # Store crop window as milliseconds for lyric sync
            dest_tags.add(TXXX(encoding=3, desc="CROP_START_MS", text=str(int(start_sec * 1000))))
            dest_tags.add(TXXX(encoding=3, desc="CROP_END_MS",   text=str(int(end_sec   * 1000))))

            dest_tags.save(dest, v2_version=3)
        except ID3NoHeaderError:
            pass

        fade_notes = []
        if need_fade_in:
            fade_notes.append(f"fade in {fade_dur}s")
        if need_fade_out:
            fade_notes.append(f"fade out {fade_dur}s")
        fade_str = f" ({', '.join(fade_notes)})" if fade_notes else ""

        print(f"Cropped {filename} [{start_str} → {end_str}]{fade_str}")
        print(f"  Saved to: {dest}")

    except Exception as e:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise e


if __name__ == "__main__":
    main()
