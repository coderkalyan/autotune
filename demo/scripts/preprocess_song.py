#!/usr/bin/env python3
"""
preprocess_song.py — Offline song preprocessing pipeline.

Steps:
  1. Split input audio into vocals + instrumental using Demucs
  2. Detect pitch on the vocal stem using librosa.pyin
  3. Write instrumental.wav, vocals.wav, pitch_track.csv, meta.json
     under demo/songs/<slug>/

Usage:
  python preprocess_song.py <input_audio> --name "Song Title" [options]

Example:
  python preprocess_song.py ~/music/bohemian_rhapsody.mp3 --name "Bohemian Rhapsody"
"""

import argparse
import csv
import json
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf
from mutagen.id3 import ID3, ID3NoHeaderError

# Sample rate used by the FPGA / backend
TARGET_SR = 48000
# Vocal frequency range (matches pitch_utils.py)
VOCAL_MIN_HZ = 80.0
VOCAL_MAX_HZ = 1100.0
# pyin frame parameters
FRAME_LENGTH = 2048
HOP_LENGTH = 512


def parse_lrc(lrc_text: str) -> list[dict]:
    """Parse LRC format ([mm:ss.xx] text) to list of {timestamp_ms, text}."""
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
    """Fetch synced lyrics from lrclib.net. Returns list of {timestamp_ms, text} or None."""
    params = urllib.parse.urlencode({"artist_name": artist, "track_name": title, "album_name": album})
    url = f"https://lrclib.net/api/get?{params}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"    WARNING: lrclib returned 404 (no match for {artist!r} / {title!r})")
        else:
            print(f"    WARNING: lrclib fetch failed: {e}")
        return None
    except Exception as e:
        print(f"    WARNING: lrclib fetch failed: {e}")
        return None
    synced = data.get("syncedLyrics")
    if not synced:
        print(f"    WARNING: lrclib has no synced lyrics for {artist!r} / {title!r}")
        return None
    return parse_lrc(synced)


def slugify(name: str) -> str:
    """Convert a song title to a filesystem-safe slug."""
    slug = name.lower().strip()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_-]+", "_", slug)
    return slug.strip("_")


def read_id3_metadata(input_path: Path) -> dict:
    """
    Read ID3 tags from an MP3 file (as written by tag_songs.py).

    Returns a dict with keys: title, artist, album, year, cover_bytes.
    Any missing field is an empty string / None.
    """
    meta = {
        "title": "", "artist": "", "album": "", "year": "",
        "cover_bytes": None,
        "crop_start_ms": None, "crop_end_ms": None,
    }
    try:
        tags = ID3(str(input_path))
    except ID3NoHeaderError:
        return meta

    if "TIT2" in tags:
        meta["title"] = str(tags["TIT2"])
    if "TPE1" in tags:
        meta["artist"] = str(tags["TPE1"])
    if "TALB" in tags:
        meta["album"] = str(tags["TALB"])
    if "TDRC" in tags:
        meta["year"] = str(tags["TDRC"])

    # Embedded album art
    apic_keys = [k for k in tags.keys() if k.startswith("APIC")]
    if apic_keys:
        meta["cover_bytes"] = tags[apic_keys[0]].data

    # Crop window written by crop_song.py
    txxx = {f.desc: f.text[0] for f in tags.getall("TXXX") if f.text}
    if "CROP_START_MS" in txxx:
        meta["crop_start_ms"] = int(txxx["CROP_START_MS"])
    if "CROP_END_MS" in txxx:
        meta["crop_end_ms"] = int(txxx["CROP_END_MS"])

    return meta


def run_demucs(input_path: Path, out_dir: Path) -> tuple[Path, Path]:
    """
    Run Demucs stem separation using the internal Python API.

    Avoids torchaudio.save() (which requires the optional torchcodec package
    in newer torchaudio releases) by calling apply_model directly and saving
    stems with soundfile.

    Returns (vocals_path, no_vocals_path).
    """
    import torch
    from demucs.apply import apply_model
    from demucs.pretrained import get_model
    from demucs.separate import load_track

    print(f"[1/3] Splitting stems with Demucs: {input_path.name}")
    device = "cuda" if torch.cuda.is_available() else "cpu"

    model = get_model("htdemucs")
    model.eval()

    # load_track returns a (channels, samples) float32 tensor at model.samplerate
    wav = load_track(input_path, model.audio_channels, model.samplerate)

    # Normalize (mirrors demucs/separate.py logic)
    ref = wav.mean(0)
    wav -= ref.mean()
    wav /= ref.std()

    # apply_model expects (batch, channels, samples); returns (batch, stems, channels, samples)
    sources = apply_model(
        model, wav[None], device=device, shifts=1, split=True, overlap=0.25, progress=True
    )[0]

    # Denormalize
    sources *= ref.std()
    sources += ref.mean()

    # sources shape: (n_stems, channels, samples); model.sources = ["drums","bass","other","vocals"]
    vocals_idx = model.sources.index("vocals")
    vocals_tensor = sources[vocals_idx]                         # (channels, samples)
    no_vocals_tensor = sources[[i for i in range(len(model.sources)) if i != vocals_idx]].sum(0)

    sr = model.samplerate
    out_paths: dict[str, Path] = {}
    for name, tensor in [("vocals", vocals_tensor), ("no_vocals", no_vocals_tensor)]:
        # (channels, samples) → (samples, channels) for soundfile
        audio = tensor.cpu().numpy().T
        dst = out_dir / f"{name}.wav"
        sf.write(str(dst), audio, sr, subtype="PCM_16")
        out_paths[name] = dst
        print(f"    Saved {name}.wav  ({sr} Hz, {audio.shape[0]/sr:.1f}s)")

    return out_paths["vocals"], out_paths["no_vocals"]


def detect_pitch(vocals_path: Path) -> tuple[np.ndarray, np.ndarray]:
    """
    Run librosa.pyin on the vocal stem.

    Returns (timestamps_ms, frequencies_hz) as 1-D numpy arrays.
    Unvoiced frames are represented as 0.0 Hz.
    """
    print(f"[2/3] Detecting pitch with librosa.pyin ...")
    y, sr = librosa.load(str(vocals_path), sr=TARGET_SR, mono=True)

    f0, voiced_flag, _ = librosa.pyin(
        y,
        fmin=VOCAL_MIN_HZ,
        fmax=VOCAL_MAX_HZ,
        sr=sr,
        frame_length=FRAME_LENGTH,
        hop_length=HOP_LENGTH,
    )

    n_frames = len(f0)
    frame_indices = np.arange(n_frames)
    timestamps_ms = librosa.frames_to_time(
        frame_indices, sr=sr, hop_length=HOP_LENGTH
    ) * 1000.0

    # Replace NaN / unvoiced with 0.0
    frequencies_hz = np.where(voiced_flag & np.isfinite(f0), f0, 0.0)

    duration_ms = float(len(y) / sr * 1000.0)
    voiced_pct = voiced_flag.sum() / n_frames * 100
    print(f"    Duration: {duration_ms/1000:.1f}s  |  Voiced frames: {voiced_pct:.1f}%")

    return timestamps_ms, frequencies_hz, duration_ms


def write_outputs(
    song_dir: Path,
    vocals_path: Path,
    no_vocals_path: Path,
    timestamps_ms: np.ndarray,
    frequencies_hz: np.ndarray,
    duration_ms: float,
    slug: str,
    name: str,
    artist: str = "",
    album: str = "",
    year: str = "",
    cover_bytes: bytes | None = None,
    crop_start_ms: int | None = None,
    crop_end_ms: int | None = None,
    lyrics: list[dict] | None = None,
) -> None:
    """Write all output files to song_dir."""
    print(f"[3/3] Writing outputs to {song_dir} ...")
    song_dir.mkdir(parents=True, exist_ok=True)

    # Copy and resample stems to TARGET_SR WAV
    for src, dst_name in [(vocals_path, "vocals.wav"), (no_vocals_path, "instrumental.wav")]:
        y, sr = librosa.load(str(src), sr=TARGET_SR, mono=False)
        # librosa loads mono by default when mono=False it returns shape (channels, samples)
        # or (samples,) for mono — soundfile expects (samples, channels) or (samples,)
        if y.ndim == 2:
            y = y.T  # (channels, samples) → (samples, channels)
        sf.write(str(song_dir / dst_name), y, TARGET_SR, subtype="PCM_16")

    # Pitch track CSV
    csv_path = song_dir / "pitch_track.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp_ms", "frequency_hz"])
        for t, hz in zip(timestamps_ms, frequencies_hz):
            writer.writerow([f"{t:.3f}", f"{hz:.4f}"])

    # Album art
    pfp = ""
    if cover_bytes:
        cover_path = song_dir / "cover.jpg"
        cover_path.write_bytes(cover_bytes)
        pfp = "cover.jpg"
        print(f"    Album art saved ({len(cover_bytes) // 1024} KB)")

    # Metadata
    meta = {
        "name": name,
        "artist": artist,
        "album": album,
        "year": year,
        "pfp": pfp,
        "slug": slug,
        "duration_ms": round(duration_ms),
        "sample_rate": TARGET_SR,
        "crop_start_ms": crop_start_ms,
        "crop_end_ms": crop_end_ms,
    }
    (song_dir / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")

    # Lyrics
    lyrics_path = song_dir / "lyrics.json"
    lyrics_data = lyrics if lyrics is not None else []
    lyrics_path.write_text(json.dumps(lyrics_data, indent=2) + "\n")
    if lyrics_data:
        print(f"    lyrics.json written ({len(lyrics_data)} lines).")
    else:
        print(f"    lyrics.json written (empty — no synced lyrics found).")

    print(f"    instrumental.wav, vocals.wav, pitch_track.csv, meta.json written.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Preprocess a song for the autotune demo.")
    parser.add_argument("input", type=Path, help="Input audio file (MP3, WAV, FLAC, ...)")
    parser.add_argument("--name", help="Human-readable song title (default: read from ID3 TIT2 tag)")
    parser.add_argument("--artist", help="Artist name override (default: read from ID3 TPE1 tag)")
    parser.add_argument("--album", help="Album name override (default: read from ID3 TALB tag)")
    parser.add_argument("--year", help="Release year override (default: read from ID3 TDRC tag)")
    parser.add_argument(
        "--songs-dir",
        type=Path,
        default=Path(__file__).parent.parent / "songs",
        help="Root songs directory (default: ../songs relative to this script)",
    )
    parser.add_argument(
        "--slug",
        help="Override filesystem slug (default: derived from --name)",
    )
    parser.add_argument(
        "--skip-lyrics",
        action="store_true",
        help="Skip fetching lyrics from lrclib.net",
    )
    args = parser.parse_args()

    input_path: Path = args.input.resolve()
    if not input_path.exists():
        sys.exit(f"Error: input file not found: {input_path}")

    # Read embedded ID3 tags; CLI args override them
    id3 = read_id3_metadata(input_path)
    name   = args.name   or id3["title"]  or input_path.stem
    artist = args.artist or id3["artist"]
    album  = args.album  or id3["album"]
    year   = args.year   or id3["year"]

    if not args.name and id3["title"]:
        print(f"  Using ID3 title: {name!r}")
    if artist:
        print(f"  Artist: {artist}")
    if album:
        print(f"  Album:  {album}")

    slug = args.slug or slugify(name)
    song_dir = args.songs_dir.resolve() / slug

    if song_dir.exists():
        print(f"Warning: {song_dir} already exists. Files will be overwritten.")

    lyrics: list[dict] | None = None
    if not args.skip_lyrics:
        print("[+] Fetching synced lyrics from lrclib.net ...")
        lyrics = fetch_lyrics(artist, name, album)

    with tempfile.TemporaryDirectory(prefix="autotune_demucs_") as tmp:
        tmp_path = Path(tmp)

        vocals_path, no_vocals_path = run_demucs(input_path, tmp_path)
        timestamps_ms, frequencies_hz, duration_ms = detect_pitch(vocals_path)
        write_outputs(
            song_dir=song_dir,
            vocals_path=vocals_path,
            no_vocals_path=no_vocals_path,
            timestamps_ms=timestamps_ms,
            frequencies_hz=frequencies_hz,
            duration_ms=duration_ms,
            slug=slug,
            name=name,
            artist=artist,
            album=album,
            year=year,
            cover_bytes=id3["cover_bytes"],
            crop_start_ms=id3["crop_start_ms"],
            crop_end_ms=id3["crop_end_ms"],
            lyrics=lyrics,
        )

    print(f"\nDone! Song '{name}' saved to: {song_dir}")


if __name__ == "__main__":
    main()
