#!/usr/bin/env python3
"""
process_all_songs.py — Makefile-style batch wrapper for preprocess_song.py.

Scans INPUT_DIR for .mp3/.wav/.flac files and runs preprocess_song.py for any
that are new, changed (by SHA-256 hash), or whose output directory is missing
required files.  Also removes output directories for songs that are no longer
in INPUT_DIR.

Usage:
  python process_all_songs.py [--dry-run] [--force] [--clean-orphans] [-j N]

  --dry-run       Print what would be done without doing it.
  --force         Reprocess all songs, ignoring cached hashes.
  --clean-orphans Remove output dirs for songs no longer in INPUT_DIR.
  -j N / --workers N
                  Run N songs in parallel (default: 1).  Each song is an
                  independent subprocess so parallelism is real — not limited
                  by the GIL.  Keep in mind Demucs is already CPU/GPU heavy;
                  set N to the number of songs you want running simultaneously.
"""

# ---------------------------------------------------------------------------
# Configuration — edit these paths to match your setup
# ---------------------------------------------------------------------------
INPUT_DIR = "scripts/downloaded_songs/cropped"  # directory of source audio files
SONGS_DIR = "songs"                              # root of preprocessed output
SCRIPTS_DIR = "scripts"                          # location of preprocess_song.py
# ---------------------------------------------------------------------------

import argparse
import hashlib
import json
import os
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

AUDIO_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"}
HASH_CACHE_FILE = ".process_cache.json"         # stored inside SONGS_DIR
REQUIRED_OUTPUTS = {"instrumental.mp3", "vocals.mp3", "pitch_track.csv", "meta.json"}

REPO_ROOT = Path(__file__).resolve().parent.parent


def resolve(p: str) -> Path:
    return (REPO_ROOT / p).resolve()


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while data := f.read(chunk):
            h.update(data)
    return h.hexdigest()


def load_cache(cache_path: Path) -> dict:
    if cache_path.exists():
        try:
            return json.loads(cache_path.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def save_cache(cache_path: Path, cache: dict) -> None:
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, indent=2) + "\n")


def outputs_complete(song_dir: Path) -> bool:
    return all((song_dir / f).exists() for f in REQUIRED_OUTPUTS)


_print_lock = threading.Lock()


def tprint(*args, **kwargs) -> None:
    """Thread-safe print."""
    with _print_lock:
        print(*args, **kwargs)


def run_preprocess(
    input_file: Path,
    songs_dir: Path,
    dry_run: bool,
    whisper_model: str,
    whisper_device: str,
) -> bool:
    """Run preprocess_song.py for one file. Returns True on success.

    Output from each subprocess is captured and flushed atomically so lines
    from concurrent jobs don't interleave.
    """
    script = resolve(SCRIPTS_DIR) / "preprocess_song.py"
    cmd = [
        sys.executable, str(script),
        str(input_file),
        "--songs-dir", str(songs_dir),
        "--whisper-model", whisper_model,
        "--whisper-device", whisper_device,
    ]
    tprint(f"  [{input_file.name}] starting ...")
    if dry_run:
        tprint(f"  [{input_file.name}] would run: {' '.join(cmd)}")
        return True

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,  # merge stderr into stdout so progress bars appear
        text=True,
        bufsize=1,                 # line-buffered
    )
    for line in proc.stdout:
        tprint(f"  [{input_file.name}] {line}", end="")
    proc.wait()
    return proc.returncode == 0


def slugify(name: str) -> str:
    """Mirror slugify() from preprocess_song.py so we can predict output dirs."""
    import re
    slug = name.lower().strip()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_-]+", "_", slug)
    return slug.strip("_")


def infer_slug(input_file: Path) -> str:
    """Best-effort slug prediction (matches preprocess_song.py default behaviour)."""
    # Try to read ID3 title first, fall back to stem
    try:
        from mutagen.id3 import ID3, ID3NoHeaderError
        try:
            tags = ID3(str(input_file))
            if "TIT2" in tags:
                return slugify(str(tags["TIT2"]))
        except ID3NoHeaderError:
            pass
    except ImportError:
        pass
    return slugify(input_file.stem)


def main() -> None:
    parser = argparse.ArgumentParser(description="Batch preprocess songs.")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done.")
    parser.add_argument("--force", action="store_true", help="Reprocess all songs.")
    parser.add_argument(
        "--clean-orphans",
        action="store_true",
        help="Remove output dirs for songs no longer in INPUT_DIR.",
    )
    parser.add_argument(
        "-j", "--workers",
        type=int,
        default=1,
        metavar="N",
        help="Number of songs to process in parallel (default: 1). "
             "Try os.cpu_count() // 4 as a starting point since Demucs is already heavy.",
    )
    parser.add_argument(
        "--whisper-model",
        default="base",
        help="Whisper model size for WhisperX (default: base). Forwarded to preprocess_song.py.",
    )
    parser.add_argument(
        "--whisper-device",
        default="cpu",
        help="Device for WhisperX: cpu or cuda (default: cpu). Forwarded to preprocess_song.py.",
    )
    args = parser.parse_args()

    input_dir = resolve(INPUT_DIR)
    songs_dir = resolve(SONGS_DIR)
    cache_path = songs_dir / HASH_CACHE_FILE

    if not input_dir.exists():
        sys.exit(f"Error: INPUT_DIR does not exist: {input_dir}")

    # Gather all audio files in input dir (non-recursive — subdirs like 'cropped' are separate)
    input_files: list[Path] = sorted(
        p for p in input_dir.iterdir()
        if p.is_file() and p.suffix.lower() in AUDIO_EXTENSIONS
    )

    if not input_files:
        print(f"No audio files found in {input_dir}")
        return

    cache = {} if args.force else load_cache(cache_path)
    new_cache: dict = {}

    to_process: list[Path] = []
    up_to_date: list[Path] = []

    print(f"Scanning {len(input_files)} file(s) in {input_dir} ...\n")

    for f in input_files:
        digest = sha256(f)
        new_cache[f.name] = digest

        slug = infer_slug(f)
        song_dir = songs_dir / slug

        cached_digest = cache.get(f.name)
        complete = outputs_complete(song_dir)

        if args.force or cached_digest != digest or not complete:
            reasons = []
            if args.force:
                reasons.append("--force")
            elif cached_digest is None:
                reasons.append("new file")
            elif cached_digest != digest:
                reasons.append("file changed")
            if not complete:
                reasons.append("output incomplete")
            print(f"  [QUEUE]  {f.name}  ({', '.join(reasons)})")
            to_process.append(f)
        else:
            print(f"  [OK]     {f.name}  (up to date)")
            up_to_date.append(f)

    # Detect orphaned output directories
    known_slugs = {infer_slug(f) for f in input_files}
    orphan_dirs: list[Path] = []
    if songs_dir.exists():
        for d in sorted(songs_dir.iterdir()):
            if d.is_dir() and d.name != ".process_cache.json" and not d.name.startswith("."):
                if d.name not in known_slugs:
                    orphan_dirs.append(d)

    if orphan_dirs:
        print(f"\nOrphaned output dirs (no matching source file):")
        for d in orphan_dirs:
            print(f"  {d.name}")
        if args.clean_orphans:
            for d in orphan_dirs:
                if args.dry_run:
                    print(f"  [DRY-RUN] Would remove {d}")
                else:
                    import shutil
                    shutil.rmtree(d)
                    print(f"  Removed {d}")
        else:
            print("  Run with --clean-orphans to delete them.")

    # Process queued files
    if not to_process:
        print("\nAll songs are up to date.")
    else:
        workers = max(1, args.workers)
        dry_tag = "  [DRY-RUN]" if args.dry_run else ""
        parallel_tag = f"  (workers={workers})" if workers > 1 else ""
        print(f"\nProcessing {len(to_process)} song(s){dry_tag}{parallel_tag} ...\n")

        failed: list[Path] = []

        with ThreadPoolExecutor(max_workers=workers) as pool:
            future_to_file = {
                pool.submit(
                    run_preprocess,
                    f,
                    songs_dir,
                    args.dry_run,
                    args.whisper_model,
                    args.whisper_device,
                ): f
                for f in to_process
            }
            for future in as_completed(future_to_file):
                f = future_to_file[future]
                try:
                    ok = future.result()
                except Exception as exc:
                    tprint(f"  [{f.name}] raised an exception: {exc}", file=sys.stderr)
                    ok = False

                if ok:
                    tprint(f"  [{f.name}] done.")
                else:
                    tprint(f"  [{f.name}] FAILED.")
                    failed.append(f)
                    # Don't cache a failed run so it retries next time
                    new_cache.pop(f.name, None)

        if failed:
            print(f"\n{len(failed)} song(s) failed:")
            for f in failed:
                print(f"  {f.name}")

    # Persist hash cache (merge with previous entries for songs not in INPUT_DIR)
    merged_cache = {**cache, **new_cache}
    # Remove cache entries for files that no longer exist in INPUT_DIR
    existing_names = {f.name for f in input_files}
    merged_cache = {k: v for k, v in merged_cache.items() if k in existing_names}

    if not args.dry_run:
        save_cache(cache_path, merged_cache)

    print("\nDone.")


if __name__ == "__main__":
    main()
