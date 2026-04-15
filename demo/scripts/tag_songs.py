#!/usr/bin/env python3
"""
Tag MP3 files with proper metadata (title, artist, album, features, album art)
using the iTunes Search API.
"""

import os
import sys
import requests
from mutagen.mp3 import MP3
from mutagen.id3 import (
    ID3, ID3NoHeaderError,
    TIT2, TPE1, TPE2, TALB, TRCK, TDRC, APIC, COMM
)

SONGS_DIR = os.path.join(os.path.dirname(__file__), "downloaded_songs")

# Map filename stem → (search_query, artist_hint, album_hint)
# album_hint narrows results when multiple versions exist (e.g. remixes, compilations).
# Set to None to accept the first artist-matching result.
SONG_QUERIES = {
    "call_me_maybe":          ("Call Me Maybe Carly Rae Jepsen",     "Carly Rae Jepsen",   None),
    "closer":                 ("Closer Chainsmokers",                "Chainsmokers",        "Collage"),
    "der_lagi_lekin":         ("Dil Lagi Lekin",                     None,                  None),
    "espresso":               ("Espresso Sabrina Carpenter",         "Sabrina Carpenter",   "Espresso - Single"),
    "i_will_always_love_you": ("I Will Always Love You Whitney Houston", "Whitney Houston", None),
    "maps":                   ("Maps Maroon 5",                      "Maroon 5",            None),
    "party_in_the_usa":       ("Party in the USA Miley Cyrus",       "Miley Cyrus",         None),
    "payphone":               ("Payphone Maroon 5 Overexposed",      "Maroon 5",            "Overexposed"),
    "shape_of_you":           ("Shape of You Ed Sheeran",            "Ed Sheeran",          None),
    "sunflower":              ("Sunflower Post Malone Swae Lee",     "Post Malone",         None),
    "viva_la_vida":           ("Viva la Vida Coldplay",              "Coldplay",            None),
}


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

    # Filter by artist hint first
    if artist_hint:
        artist_lower = artist_hint.lower()
        artist_matches = [r for r in results if artist_lower in r.get("artistName", "").lower()]
        if artist_matches:
            results = artist_matches

    # Within artist matches, prefer one where album contains the album hint
    if album_hint:
        album_lower = album_hint.lower()
        album_matches = [r for r in results if album_lower in r.get("collectionName", "").lower()]
        if album_matches:
            return album_matches[0]

    return results[0]


def download_image(url: str) -> bytes | None:
    """Download album art bytes from URL (use 600x600 version)."""
    # iTunes returns 100x100 by default; swap for 600x600
    url = url.replace("100x100bb", "600x600bb")
    try:
        r = requests.get(url, timeout=15)
        r.raise_for_status()
        return r.content
    except Exception as e:
        print(f"  Image download error: {e}")
        return None


def tag_file(mp3_path: str, stem: str) -> None:
    query, artist_hint, album_hint = SONG_QUERIES.get(stem, (stem, None, None))
    print(f"\n[{stem}]")
    print(f"  Searching iTunes: {query!r}")

    result = itunes_lookup(query, artist_hint, album_hint)
    if not result:
        print("  No iTunes result found — skipping.")
        return

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

    # Load or create ID3 tag
    try:
        tags = ID3(mp3_path)
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

    # Album art
    if artwork_url:
        img_data = download_image(artwork_url)
        if img_data:
            tags.delall("APIC")
            tags.add(APIC(
                encoding=3,
                mime="image/jpeg",
                type=3,       # Cover (front)
                desc="Cover",
                data=img_data,
            ))
            print(f"  Album art embedded ({len(img_data)//1024} KB)")
        else:
            print("  Album art download failed.")

    tags.save(mp3_path, v2_version=3)
    print("  Tags saved.")


def main():
    for filename in sorted(os.listdir(SONGS_DIR)):
        if not filename.endswith(".mp3"):
            continue
        stem = filename[:-4]  # strip .mp3
        if stem not in SONG_QUERIES:
            print(f"\n[{stem}] — no query mapping, skipping.")
            continue
        mp3_path = os.path.join(SONGS_DIR, filename)
        tag_file(mp3_path, stem)

    print("\nDone.")


if __name__ == "__main__":
    main()
