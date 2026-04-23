#!/usr/bin/env python3
"""
fetch_lyrics.py — Fetch and save synced lyrics for existing songs.

Reads meta.json from each song directory, fetches synced lyrics from
lrclib.net, and writes lyrics.json without re-running Demucs or pyin.

Usage:
  python fetch_lyrics.py                    # all songs in ../songs/
  python fetch_lyrics.py songs/call_me_maybe songs/espresso
  python fetch_lyrics.py --songs-dir /path/to/songs
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def parse_lrc(lrc_text: str) -> list[dict]:
    pattern = re.compile(r"\[(\d+):(\d+\.\d+)\](.*)")
    lines = []
    for line in lrc_text.splitlines():
        m = pattern.match(line.strip())
        if not m:
            continue
        ts_ms = (int(m.group(1)) * 60 + float(m.group(2))) * 1000
        text = m.group(3).strip()
        lines.append({"timestamp_ms": round(ts_ms, 3), "text": text})
    return lines


def fetch_lyrics(artist: str, title: str, album: str = "") -> list[dict] | None:
    params = urllib.parse.urlencode({"artist_name": artist, "track_name": title, "album_name": album})
    url = f"https://lrclib.net/api/get?{params}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"  WARNING: no match on lrclib (404)")
        else:
            print(f"  WARNING: lrclib HTTP error: {e}")
        return None
    except Exception as e:
        print(f"  WARNING: lrclib fetch failed: {e}")
        return None
    synced = data.get("syncedLyrics")
    if not synced:
        print(f"  WARNING: lrclib has no synced lyrics")
        return None
    return parse_lrc(synced)


def process_song_dir(song_dir: Path, overwrite: bool) -> bool:
    meta_path = song_dir / "meta.json"
    if not meta_path.exists():
        print(f"  SKIP: no meta.json in {song_dir}")
        return False

    lyrics_path = song_dir / "lyrics.json"
    if lyrics_path.exists() and not overwrite:
        print(f"  SKIP: lyrics.json already exists (use --overwrite to replace)")
        return False

    with open(meta_path) as f:
        meta = json.load(f)

    name = meta.get("name", song_dir.name)
    artist = meta.get("artist", "")
    album = meta.get("album", "")

    print(f"Fetching: {name!r} by {artist!r} ...")
    lyrics = fetch_lyrics(artist, name, album)
    data = lyrics if lyrics is not None else []
    lyrics_path.write_text(json.dumps(data, indent=2) + "\n")

    if data:
        print(f"  OK: {len(data)} lines → {lyrics_path}")
    else:
        print(f"  EMPTY: wrote empty lyrics.json → {lyrics_path}")

    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch synced lyrics for existing songs.")
    parser.add_argument(
        "song_dirs",
        nargs="*",
        type=Path,
        help="Specific song directories to process (default: all songs in --songs-dir)",
    )
    parser.add_argument(
        "--songs-dir",
        type=Path,
        default=Path(__file__).parent.parent / "songs",
        help="Root songs directory (default: ../songs relative to this script)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing lyrics.json files",
    )
    args = parser.parse_args()

    if args.song_dirs:
        dirs = [d.resolve() for d in args.song_dirs]
    else:
        songs_dir = args.songs_dir.resolve()
        if not songs_dir.is_dir():
            sys.exit(f"Error: songs directory not found: {songs_dir}")
        dirs = sorted(d for d in songs_dir.iterdir() if d.is_dir() and (d / "meta.json").exists())
        if not dirs:
            sys.exit(f"Error: no song directories found in {songs_dir}")

    ok = sum(process_song_dir(d, args.overwrite) for d in dirs)
    print(f"\nDone: processed {ok}/{len(dirs)} song(s).")


if __name__ == "__main__":
    main()
