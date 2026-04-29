#!/usr/bin/env python3
"""
Lossless crop: stream-copy the audio between [start, end] into a sibling
'cropped/' folder, leaving the original untouched. No fade in/out (apply
those later if needed). Output keeps the source extension (mp3 → mp3,
flac → flac, …).

Optionally tag a sing-along grading window. Grade times are given in
ORIGINAL-song time (must lie inside [start, end]); they are stored as
clip-relative ms in the output's tag block (ID3 TXXX for MP3, Vorbis
comments for FLAC).

Usage:
    python3 crop_song.py <file> <start> <end> [-gs TIME] [-ge TIME]

Times: seconds (90), MM:SS (1:30), or HH:MM:SS (0:01:30).
Output: <parent_dir>/cropped/<filename>
"""

import argparse
import os
import subprocess
import sys
import tempfile

from mutagen.id3 import ID3, ID3NoHeaderError, TXXX
from mutagen.flac import FLAC, Picture as FLACPicture


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


def write_tags_mp3(
    dest: str,
    crop_start_ms: int,
    crop_end_ms: int,
    grade_start_clip_ms: int | None,
    grade_end_clip_ms: int | None,
) -> None:
    try:
        tags = ID3(dest)
    except ID3NoHeaderError:
        tags = ID3()

    tags.delall("TXXX:CROP_START_MS")
    tags.delall("TXXX:CROP_END_MS")
    tags.add(TXXX(encoding=3, desc="CROP_START_MS", text=str(crop_start_ms)))
    tags.add(TXXX(encoding=3, desc="CROP_END_MS", text=str(crop_end_ms)))

    tags.delall("TXXX:GRADE_START_MS")
    tags.delall("TXXX:GRADE_END_MS")
    if grade_start_clip_ms is not None:
        tags.add(TXXX(encoding=3, desc="GRADE_START_MS", text=str(grade_start_clip_ms)))
        tags.add(TXXX(encoding=3, desc="GRADE_END_MS", text=str(grade_end_clip_ms)))

    tags.save(dest, v2_version=3)


def write_tags_flac(
    src: str,
    dest: str,
    crop_start_ms: int,
    crop_end_ms: int,
    grade_start_clip_ms: int | None,
    grade_end_clip_ms: int | None,
) -> None:
    flac = FLAC(dest)
    # Vorbis comment field names are conventionally case-insensitive.
    flac["CROP_START_MS"] = str(crop_start_ms)
    flac["CROP_END_MS"] = str(crop_end_ms)
    if grade_start_clip_ms is not None:
        flac["GRADE_START_MS"] = str(grade_start_clip_ms)
        flac["GRADE_END_MS"] = str(grade_end_clip_ms)
    else:
        for k in ("GRADE_START_MS", "GRADE_END_MS"):
            if k in flac:
                del flac[k]

    # ffmpeg's FLAC re-encode drops native PICTURE blocks; re-attach from source.
    if not flac.pictures:
        try:
            src_flac = FLAC(src)
            for pic in src_flac.pictures:
                new_pic = FLACPicture()
                new_pic.type = pic.type
                new_pic.mime = pic.mime
                new_pic.desc = pic.desc
                new_pic.width = pic.width
                new_pic.height = pic.height
                new_pic.depth = pic.depth
                new_pic.colors = pic.colors
                new_pic.data = pic.data
                flac.add_picture(new_pic)
        except Exception as e:
            print(f"Warning: could not reattach FLAC cover art ({e}).")

    flac.save()


def main():
    parser = argparse.ArgumentParser(
        description="Lossless crop (stream-copy) with optional grading-window tags.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Times accept seconds (90), MM:SS (1:30), or HH:MM:SS (0:01:30).\n"
            "Grade times are ORIGINAL-song time and must lie inside [start, end]."
        ),
    )
    parser.add_argument("file", help="Source audio file (mp3, flac, ...)")
    parser.add_argument("start", help="Crop start time")
    parser.add_argument("end", help="Crop end time")
    parser.add_argument(
        "-gs", "--grade-start", default=None,
        help="Grading window start in ORIGINAL-song time (optional).",
    )
    parser.add_argument(
        "-ge", "--grade-end", default=None,
        help="Grading window end in ORIGINAL-song time (optional).",
    )
    args = parser.parse_args()

    src = args.file
    if not os.path.isfile(src):
        sys.exit(f"Error: file not found: {src}")

    src_abs = os.path.abspath(src)
    src_dir = os.path.dirname(src_abs)
    filename = os.path.basename(src_abs)
    ext = os.path.splitext(filename)[1].lower()

    if ext not in (".mp3", ".flac"):
        sys.exit(
            f"Error: unsupported source extension {ext!r}. "
            "Only .mp3 and .flac are tagged; add a writer for other formats."
        )

    start_sec = parse_seconds(args.start)
    end_sec = parse_seconds(args.end)
    total_dur = get_duration(src_abs)

    if end_sec <= start_sec:
        sys.exit(f"Error: end ({end_sec}) must be > start ({start_sec}).")
    if start_sec < 0:
        sys.exit("Error: start must be non-negative.")
    if end_sec > total_dur + 0.5:
        sys.exit(
            f"Error: end ({end_sec}s) past source duration ({total_dur:.3f}s)."
        )

    clip_dur = end_sec - start_sec

    # Grade window: user gives ORIGINAL-song time; we store it clip-relative.
    grade_start_orig: float | None = (
        parse_seconds(args.grade_start) if args.grade_start is not None else None
    )
    grade_end_orig: float | None = (
        parse_seconds(args.grade_end) if args.grade_end is not None else None
    )
    if (grade_start_orig is None) != (grade_end_orig is None):
        sys.exit("Error: --grade-start and --grade-end must be set together.")
    grade_start_clip: float | None = None
    grade_end_clip: float | None = None
    if grade_start_orig is not None:
        if grade_end_orig <= grade_start_orig:
            sys.exit("Error: --grade-end must be greater than --grade-start.")
        if grade_start_orig < start_sec - 1e-3 or grade_end_orig > end_sec + 1e-3:
            sys.exit(
                f"Error: grade window [{grade_start_orig}, {grade_end_orig}] "
                f"outside crop [{start_sec}, {end_sec}]."
            )
        grade_start_clip = max(0.0, grade_start_orig - start_sec)
        grade_end_clip = min(clip_dur, grade_end_orig - start_sec)

    cropped_dir = os.path.join(src_dir, "cropped")
    os.makedirs(cropped_dir, exist_ok=True)
    dest = os.path.join(cropped_dir, filename)

    tmp_fd, tmp_path = tempfile.mkstemp(suffix=ext, dir=cropped_dir)
    os.close(tmp_fd)

    try:
        # MP3: stream-copy (lossless, frame-aligned).
        # FLAC: re-encode to FLAC. Stream-copy on FLAC leaves the source's
        #   STREAMINFO total_samples intact, so players show the wrong
        #   length and run past the cropped audio. FLAC re-encode is
        #   bit-exact on the decoded PCM, so it's still lossless.
        if ext == ".mp3":
            cmd = [
                "ffmpeg", "-y",
                "-ss", args.start,
                "-to", args.end,
                "-i", src_abs,
                "-c", "copy",
                "-map_metadata", "0",
                tmp_path,
            ]
        else:  # .flac
            cmd = [
                "ffmpeg", "-y",
                "-i", src_abs,
                "-ss", args.start,
                "-to", args.end,
                "-c:a", "flac",
                "-compression_level", "5",
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

        crop_start_ms = int(start_sec * 1000)
        crop_end_ms = int(end_sec * 1000)
        gs_clip_ms = int(grade_start_clip * 1000) if grade_start_clip is not None else None
        ge_clip_ms = int(grade_end_clip * 1000) if grade_end_clip is not None else None

        try:
            if ext == ".mp3":
                write_tags_mp3(dest, crop_start_ms, crop_end_ms, gs_clip_ms, ge_clip_ms)
            elif ext == ".flac":
                write_tags_flac(src_abs, dest, crop_start_ms, crop_end_ms, gs_clip_ms, ge_clip_ms)
        except Exception as e:
            print(f"Warning: tag write failed ({e}); audio still saved.")

        notes = ["mp3 stream-copy" if ext == ".mp3" else "flac re-encode (lossless)"]
        if grade_start_orig is not None:
            notes.append(
                f"grade orig {grade_start_orig:.2f}–{grade_end_orig:.2f}s "
                f"(clip {grade_start_clip:.2f}–{grade_end_clip:.2f}s)"
            )
        suffix = f" ({', '.join(notes)})"
        print(f"Cropped {filename} [{args.start} → {args.end}]{suffix}")
        print(f"  Saved to: {dest}")

    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


if __name__ == "__main__":
    main()
