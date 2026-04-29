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
import bisect
import csv
import json
import re
import statistics
import sys
import tempfile
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf
from mutagen.id3 import ID3, ID3NoHeaderError
from mutagen.flac import FLAC, Picture as FLACPicture

from whisperx_lyrics import transcribe_lyrics

# Sample rate used by the FPGA / backend
TARGET_SR = 48000
# Vocal frequency range (matches pitch_utils.py)
VOCAL_MIN_HZ = 80.0
VOCAL_MAX_HZ = 1100.0
# pyin frame parameters
FRAME_LENGTH = 2048
HOP_LENGTH = 512


def slugify(name: str) -> str:
    """Convert a song title to a filesystem-safe slug."""
    slug = name.lower().strip()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_-]+", "_", slug)
    return slug.strip("_")


def read_id3_metadata(input_path: Path) -> dict:
    """
    Read embedded tags from an MP3 (ID3) or FLAC (Vorbis comments) file.

    Returns a dict with keys: title, artist, album, year, cover_bytes,
    crop_start_ms, crop_end_ms, grade_start_ms, grade_end_ms.
    Any missing field is empty string / None.
    """
    meta = {
        "title": "", "artist": "", "album": "", "year": "",
        "cover_bytes": None,
        "crop_start_ms": None, "crop_end_ms": None,
        "grade_start_ms": None, "grade_end_ms": None,
    }
    ext = input_path.suffix.lower()
    if ext == ".flac":
        return _read_flac_metadata(input_path, meta)
    return _read_mp3_metadata(input_path, meta)


def _read_mp3_metadata(input_path: Path, meta: dict) -> dict:
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

    apic_keys = [k for k in tags.keys() if k.startswith("APIC")]
    if apic_keys:
        meta["cover_bytes"] = tags[apic_keys[0]].data

    txxx = {f.desc: f.text[0] for f in tags.getall("TXXX") if f.text}
    if "CROP_START_MS" in txxx:
        meta["crop_start_ms"] = int(txxx["CROP_START_MS"])
    if "CROP_END_MS" in txxx:
        meta["crop_end_ms"] = int(txxx["CROP_END_MS"])
    if "GRADE_START_MS" in txxx:
        meta["grade_start_ms"] = int(txxx["GRADE_START_MS"])
    if "GRADE_END_MS" in txxx:
        meta["grade_end_ms"] = int(txxx["GRADE_END_MS"])

    return meta


def _read_flac_metadata(input_path: Path, meta: dict) -> dict:
    try:
        flac = FLAC(str(input_path))
    except Exception:
        return meta

    def _first(key: str) -> str:
        v = flac.get(key)
        if not v:
            return ""
        return str(v[0]) if isinstance(v, list) else str(v)

    meta["title"] = _first("title")
    meta["artist"] = _first("artist")
    meta["album"] = _first("album")
    meta["year"] = _first("date") or _first("year")

    if flac.pictures:
        meta["cover_bytes"] = flac.pictures[0].data

    # Vorbis comments are case-insensitive but mutagen normalizes to lower-case keys.
    def _int(key: str) -> int | None:
        v = flac.get(key.lower()) or flac.get(key)
        if not v:
            return None
        try:
            return int(v[0]) if isinstance(v, list) else int(v)
        except (TypeError, ValueError):
            return None

    meta["crop_start_ms"] = _int("CROP_START_MS")
    meta["crop_end_ms"] = _int("CROP_END_MS")
    meta["grade_start_ms"] = _int("GRADE_START_MS")
    meta["grade_end_ms"] = _int("GRADE_END_MS")

    return meta


def run_demucs(input_path: Path, out_dir: Path, model_name: str = "htdemucs_ft") -> tuple[Path, Path]:
    """
    Run Demucs stem separation using the internal Python API.

    Avoids torchaudio.save() (which requires the optional torchcodec package
    in newer torchaudio releases) by calling apply_model directly and saving
    stems with soundfile.

    `model_name` defaults to htdemucs_ft (fine-tuned, higher SDR, ~4x slower).
    Pass "htdemucs" for the faster base model.

    Returns (vocals_path, no_vocals_path).
    """
    import torch
    from demucs.apply import apply_model
    from demucs.pretrained import get_model
    from demucs.separate import load_track

    print(f"[1/3] Splitting stems with Demucs ({model_name}): {input_path.name}")
    device = "cuda" if torch.cuda.is_available() else "cpu"

    model = get_model(model_name)
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


def _apply_fade(y: np.ndarray, sr: int, fade_in_sec: float, fade_out_sec: float) -> np.ndarray:
    """Apply linear fade-in/out in-place. Mono (samples,) or stereo (samples, ch)."""
    n = y.shape[0]
    if fade_in_sec > 0:
        fi = min(int(fade_in_sec * sr), n)
        if fi > 0:
            ramp = np.linspace(0.0, 1.0, fi, dtype=y.dtype)
            if y.ndim == 2:
                y[:fi] *= ramp[:, None]
            else:
                y[:fi] *= ramp
    if fade_out_sec > 0:
        fo = min(int(fade_out_sec * sr), n)
        if fo > 0:
            ramp = np.linspace(1.0, 0.0, fo, dtype=y.dtype)
            if y.ndim == 2:
                y[-fo:] *= ramp[:, None]
            else:
                y[-fo:] *= ramp
    return y


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
    grade_start_ms: int | None = None,
    grade_end_ms: int | None = None,
    lyrics: list[dict] | None = None,
    fade_in_sec: float = 1.5,
    fade_out_sec: float = 2.0,
) -> None:
    """Write all output files to song_dir. Stems land as MP3 at TARGET_SR."""
    print(f"[3/3] Writing outputs to {song_dir} ...")
    song_dir.mkdir(parents=True, exist_ok=True)

    # Drop any stale .wav stems from older preprocess runs so we don't have
    # both formats sitting next to each other.
    for stale in (song_dir / "vocals.wav", song_dir / "instrumental.wav"):
        if stale.exists():
            stale.unlink()

    # Resample stems to TARGET_SR, apply fades, write MP3.
    for src, dst_name in [(vocals_path, "vocals.mp3"), (no_vocals_path, "instrumental.mp3")]:
        y, sr = librosa.load(str(src), sr=TARGET_SR, mono=False)
        # librosa returns (channels, samples) for stereo; soundfile wants
        # (samples, channels) or (samples,) for mono.
        if y.ndim == 2:
            y = y.T
        y = np.ascontiguousarray(y, dtype=np.float32)
        _apply_fade(y, TARGET_SR, fade_in_sec, fade_out_sec)
        sf.write(str(song_dir / dst_name), y, TARGET_SR, format="MP3")

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
        "grade_start_ms": grade_start_ms,
        "grade_end_ms": grade_end_ms,
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

    # Notes (per-word target chart for karaoke scoring)
    notes = derive_notes_from_lyrics(
        lyrics_data,
        timestamps_ms.tolist(),
        frequencies_hz.tolist(),
    )
    notes_path = song_dir / "notes.json"
    notes_path.write_text(json.dumps(notes, indent=2) + "\n")
    if notes:
        print(f"    notes.json written ({len(notes)} notes).")
    else:
        print(f"    notes.json written (empty — no lyrics or no voiced pitch).")

    print(f"    instrumental.mp3, vocals.mp3, pitch_track.csv, meta.json written.")


def derive_notes_from_lyrics(
    lyrics: list[dict],
    pitch_timestamps: list[float],
    pitch_freqs: list[float],
) -> list[dict]:
    """One note per lyric word; pitch = median of voiced pitch_track samples
    falling inside the word's [start, end). Mirrors backend/song_manager.py.
    """
    notes: list[dict] = []
    for line in lyrics:
        words = line.get("words") or []
        for w in words:
            start = float(w["timestamp_ms"])
            end_raw = w.get("end_ms")
            end = float(end_raw) if end_raw is not None else start + 200.0
            if end <= start:
                continue
            lo = bisect.bisect_left(pitch_timestamps, start)
            hi = bisect.bisect_left(pitch_timestamps, end)
            voiced = [f for f in pitch_freqs[lo:hi] if f > 0.0]
            if not voiced:
                continue
            notes.append(
                {
                    "start_ms": start,
                    "duration_ms": end - start,
                    "pitch_hz": float(statistics.median(voiced)),
                    "lyric": str(w.get("text", "")),
                }
            )
    notes.sort(key=lambda n: n["start_ms"])
    return notes


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
        help="Skip lyric transcription (WhisperX)",
    )
    parser.add_argument(
        "--whisper-model",
        default="base",
        help="Whisper model size for WhisperX (default: base)",
    )
    parser.add_argument(
        "--whisper-device",
        default="cpu",
        help="Device for WhisperX: cpu or cuda (default: cpu)",
    )
    parser.add_argument(
        "--fade-in", type=float, default=1.5,
        help="Fade-in seconds applied to output stems (default: 1.5)",
    )
    parser.add_argument(
        "--fade-out", type=float, default=2.0,
        help="Fade-out seconds applied to output stems (default: 2.0)",
    )
    parser.add_argument(
        "--demucs-model", default="htdemucs_ft",
        help="Demucs model name: htdemucs_ft (default, best), htdemucs (faster), htdemucs_6s, mdx_extra.",
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

    with tempfile.TemporaryDirectory(prefix="autotune_demucs_") as tmp:
        tmp_path = Path(tmp)

        vocals_path, no_vocals_path = run_demucs(input_path, tmp_path, args.demucs_model)
        timestamps_ms, frequencies_hz, duration_ms = detect_pitch(vocals_path)

        lyrics: list[dict] | None = None
        if not args.skip_lyrics:
            print("[+] Transcribing word-level lyrics with WhisperX ...")
            try:
                lyrics = transcribe_lyrics(vocals_path, args.whisper_model, args.whisper_device)
            except Exception as e:
                print(f"    WARNING: WhisperX transcription failed: {e}")
                lyrics = None

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
            grade_start_ms=id3["grade_start_ms"],
            grade_end_ms=id3["grade_end_ms"],
            lyrics=lyrics,
            fade_in_sec=args.fade_in,
            fade_out_sec=args.fade_out,
        )

    print(f"\nDone! Song '{name}' saved to: {song_dir}")


if __name__ == "__main__":
    main()
