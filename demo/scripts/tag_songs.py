#!/usr/bin/env python3
"""
Tag MP3 files with proper metadata (title, artist, album, year, album art)
using the iTunes Search API.

Default workflow:
  - Reads MP3s from `downloaded_songs/new/` (typical YouTube-dl filenames like
    "Artist - Title (Official Video) [YT_ID].mp3").
  - Parses artist/title from the filename, queries iTunes for canonical metadata.
  - Writes ID3 tags + embedded cover art.
  - Renames the file to `<slug>.mp3` and moves it to `downloaded_songs/keep/`.

Override the auto-parsed query for a given filename stem via SONG_QUERIES.

Usage:
  python tag_songs.py                                   # batch new/ → keep/
  python tag_songs.py path/to/song.mp3                  # hotswap one file (tag + rename in place)
  python tag_songs.py a.mp3 b.mp3 c.mp3                 # hotswap several
  python tag_songs.py --input-dir downloaded_songs/new --output-dir downloaded_songs/keep
  python tag_songs.py --no-move                         # batch mode, tag in place
"""

import argparse
import re
import shutil
import sys
from pathlib import Path

import requests
from mutagen.id3 import (
    ID3, ID3NoHeaderError,
    TIT2, TPE1, TPE2, TALB, TRCK, TDRC, APIC,
)

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_INPUT_DIR = SCRIPT_DIR / "downloaded_songs" / "new"
DEFAULT_OUTPUT_DIR = SCRIPT_DIR / "downloaded_songs" / "keep"

# Optional per-stem overrides: parsed-title-slug → (search_query, artist_hint, album_hint)
SONG_QUERIES: dict[str, tuple[str, str | None, str | None]] = {
    "closer":   ("Closer Chainsmokers",        "Chainsmokers",      "Collage"),
    "espresso": ("Espresso Sabrina Carpenter", "Sabrina Carpenter", "Espresso - Single"),
    "payphone": ("Payphone Maroon 5",          "Maroon 5",          "Overexposed"),
}


# ---------------------------------------------------------------------------
# Filename parsing
# ---------------------------------------------------------------------------

_ANNOTATION_RE = re.compile(
    r"""\s*[\(\[]\s*(?:
        official[^)\]]*|
        music\s+video|
        audio|
        lyrics?|
        hd|hq|4k|
        from[^)\]]*|
        feat\.?[^)\]]*|
        ft\.?[^)\]]*
    )\s*[\)\]]""",
    re.IGNORECASE | re.VERBOSE,
)
_YT_ID_RE = re.compile(r"\s*\[[A-Za-z0-9_\-]{6,15}\]\s*$")


def parse_filename(stem: str) -> tuple[str, str]:
    """Extract (artist, title) from a YouTube-dl style filename stem."""
    s = stem
    s = s.replace("＂", '"').replace("⧸", "/")

    s = _YT_ID_RE.sub("", s).strip()

    while True:
        new = _ANNOTATION_RE.sub("", s).strip()
        if new == s:
            break
        s = new

    if " - " in s:
        artist, title = s.split(" - ", 1)
    else:
        artist, title = "", s

    return artist.strip(), title.strip()


def slugify(text: str) -> str:
    """Lowercase, replace non-word chars with underscores. Mirrors preprocess_song.slugify."""
    s = text.lower().strip()
    s = re.sub(r"[^\w\s-]", "", s)
    s = re.sub(r"[\s_-]+", "_", s)
    return s.strip("_")


# ---------------------------------------------------------------------------
# iTunes lookup
# ---------------------------------------------------------------------------

def itunes_lookup(query: str, artist_hint: str | None, album_hint: str | None) -> dict | None:
    """Search iTunes and return the best matching track result."""
    url = "https://itunes.apple.com/search"
    params = {"term": query, "media": "music", "entity": "song", "limit": 10}
    try:
        r = requests.get(url, params=params, timeout=10)
        r.raise_for_status()
        results = r.json().get("results", [])
    except Exception as e:
        print(f"  iTunes API error: {e}")
        return None

    if not results:
        return None

    if artist_hint:
        artist_lower = artist_hint.lower()
        artist_matches = [r for r in results if artist_lower in r.get("artistName", "").lower()]
        if artist_matches:
            results = artist_matches

    if album_hint:
        album_lower = album_hint.lower()
        album_matches = [r for r in results if album_lower in r.get("collectionName", "").lower()]
        if album_matches:
            return album_matches[0]

    return results[0]


def download_image(url: str) -> bytes | None:
    """Download album art bytes (use 600x600 version)."""
    url = url.replace("100x100bb", "600x600bb")
    try:
        r = requests.get(url, timeout=15)
        r.raise_for_status()
        return r.content
    except Exception as e:
        print(f"  Image download error: {e}")
        return None


# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

def tag_file(mp3_path: Path) -> tuple[bool, str | None]:
    """Tag an MP3 in place. Returns (success, slug-of-tagged-title)."""
    raw_stem = mp3_path.stem
    parsed_artist, parsed_title = parse_filename(raw_stem)
    print(f"\n[{raw_stem}]")
    print(f"  Parsed: artist={parsed_artist!r}  title={parsed_title!r}")

    parsed_slug = slugify(parsed_title) if parsed_title else slugify(raw_stem)
    if parsed_slug in SONG_QUERIES:
        query, artist_hint, album_hint = SONG_QUERIES[parsed_slug]
        print(f"  Using override query: {query!r}")
    else:
        query = f"{parsed_title} {parsed_artist}".strip() or raw_stem
        artist_hint = parsed_artist or None
        album_hint = None

    print(f"  Searching iTunes: {query!r}")
    result = itunes_lookup(query, artist_hint, album_hint)
    if not result:
        print("  No iTunes result found — skipping.")
        return False, None

    title       = result.get("trackName", "")
    artist      = result.get("artistName", "")
    album       = result.get("collectionName", "")
    year        = str(result.get("releaseDate", ""))[:4]
    track_num   = result.get("trackNumber")
    artwork_url = result.get("artworkUrl100", "")

    print(f"  Title:  {title}")
    print(f"  Artist: {artist}")
    print(f"  Album:  {album}")
    print(f"  Year:   {year}")

    try:
        tags = ID3(str(mp3_path))
    except ID3NoHeaderError:
        tags = ID3()

    tags.delall("TIT2"); tags.add(TIT2(encoding=3, text=title))
    tags.delall("TPE1"); tags.add(TPE1(encoding=3, text=artist))
    tags.delall("TPE2"); tags.add(TPE2(encoding=3, text=artist))
    tags.delall("TALB"); tags.add(TALB(encoding=3, text=album))
    if year:
        tags.delall("TDRC"); tags.add(TDRC(encoding=3, text=year))
    if track_num:
        tags.delall("TRCK"); tags.add(TRCK(encoding=3, text=str(track_num)))

    if artwork_url:
        img_data = download_image(artwork_url)
        if img_data:
            tags.delall("APIC")
            tags.add(APIC(
                encoding=3,
                mime="image/jpeg",
                type=3,
                desc="Cover",
                data=img_data,
            ))
            print(f"  Album art embedded ({len(img_data)//1024} KB)")
        else:
            print("  Album art download failed.")

    tags.save(str(mp3_path), v2_version=3)
    print("  Tags saved.")
    return True, slugify(title)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def hotswap(mp3: Path) -> None:
    """Tag one MP3 in place and rename it to <slug>.mp3 in the same directory."""
    ok, slug = tag_file(mp3)
    if not ok:
        return
    if not slug:
        print("  WARNING: empty slug from iTunes title — leaving filename as-is.")
        return
    dst = mp3.parent / f"{slug}.mp3"
    if dst == mp3:
        print(f"  Filename already matches slug ({mp3.name}).")
        return
    if dst.exists():
        print(f"  WARNING: {dst.name} already exists in {mp3.parent} — not renaming.")
        return
    mp3.rename(dst)
    print(f"  Renamed → {dst}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("files", nargs="*", type=Path,
                    help="One or more MP3 files to hotswap (tag + rename to <slug>.mp3 in place)")
    ap.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT_DIR,
                    help=f"Batch mode input dir (default: {DEFAULT_INPUT_DIR})")
    ap.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR,
                    help=f"Batch mode output dir (default: {DEFAULT_OUTPUT_DIR})")
    ap.add_argument("--no-move", action="store_true",
                    help="Batch mode: tag in place, don't move/rename")
    args = ap.parse_args()

    # Hotswap mode: explicit files
    if args.files:
        for f in args.files:
            f = f.resolve()
            if not f.is_file():
                print(f"\n[{f}] — not a file, skipping.")
                continue
            if f.suffix.lower() != ".mp3":
                print(f"\n[{f.name}] — not an .mp3, skipping.")
                continue
            hotswap(f)
        print("\nDone.")
        return

    # Batch mode: scan input-dir, move tagged files to output-dir
    input_dir: Path = args.input_dir.resolve()
    output_dir: Path = args.output_dir.resolve()

    if not input_dir.is_dir():
        sys.exit(f"Error: input dir not found: {input_dir}")

    if not args.no_move:
        output_dir.mkdir(parents=True, exist_ok=True)

    mp3s = sorted(p for p in input_dir.iterdir() if p.suffix.lower() == ".mp3")
    if not mp3s:
        print(f"No MP3 files in {input_dir}")
        return

    for mp3 in mp3s:
        ok, slug = tag_file(mp3)
        if not ok or args.no_move:
            continue
        if not slug:
            print("  WARNING: empty slug from iTunes title — leaving in place.")
            continue
        dst = output_dir / f"{slug}.mp3"
        if dst.exists():
            print(f"  WARNING: {dst} already exists — leaving original in place.")
            continue
        shutil.move(str(mp3), str(dst))
        print(f"  Moved → {dst}")

    print("\nDone.")


if __name__ == "__main__":
    main()
