import bisect
import csv
import json
import os
import statistics

from scoring import Note


class SongManager:
    def __init__(self, songs_dir: str) -> None:
        self._songs_dir = os.path.abspath(songs_dir)
        self._current_song_id: str | None = None
        self._timestamps: list[float] = []
        self._freqs: list[float] = []
        self._lyric_times: list[float] = []
        self._lyric_texts: list[str] = []
        self._notes: list[Note] = []

    # ------------------------------------------------------------------
    # Song catalogue
    # ------------------------------------------------------------------

    def list_songs(self) -> list[dict]:
        songs = []
        for entry in sorted(os.listdir(self._songs_dir)):
            meta_path = os.path.join(self._songs_dir, entry, "meta.json")
            if not os.path.isfile(meta_path):
                continue
            with open(meta_path) as f:
                meta = json.load(f)
            slug = meta.get("slug", entry)
            songs.append(
                {
                    "id": slug,
                    "title": meta.get("name", slug),
                    "artist": meta.get("artist", ""),
                    "album": meta.get("album", ""),
                    "duration_ms": meta.get("duration_ms", 0),
                    "album_art_url": f"/songs/{slug}/cover",
                    "bpm": meta.get("bpm", None),
                }
            )
        return songs

    def song_dir(self, song_id: str) -> str:
        return os.path.join(self._songs_dir, song_id)

    def _stem_path(self, song_id: str, base: str) -> str:
        """Find <base>.{mp3,wav} in the song dir; default to .mp3 if neither exists."""
        d = self.song_dir(song_id)
        for ext in (".mp3", ".wav"):
            p = os.path.join(d, base + ext)
            if os.path.isfile(p):
                return p
        return os.path.join(d, base + ".mp3")

    def instrumental_path(self, song_id: str) -> str:
        return self._stem_path(song_id, "instrumental")

    def cover_path(self, song_id: str) -> str:
        return os.path.join(self.song_dir(song_id), "cover.jpg")

    def vocals_path(self, song_id: str) -> str:
        return self._stem_path(song_id, "vocals")

    # ------------------------------------------------------------------
    # Pitch track
    # ------------------------------------------------------------------

    def load(self, song_id: str) -> None:
        pitch_path = os.path.join(self.song_dir(song_id), "pitch_track.csv")
        timestamps: list[float] = []
        freqs: list[float] = []
        with open(pitch_path, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                timestamps.append(float(row["timestamp_ms"]))
                freqs.append(float(row["frequency_hz"]))
        self._timestamps = timestamps
        self._freqs = freqs

        lyric_times: list[float] = []
        lyric_texts: list[str] = []
        lyrics_raw: list[dict] = []
        lyrics_path = os.path.join(self.song_dir(song_id), "lyrics.json")
        if os.path.isfile(lyrics_path):
            with open(lyrics_path) as f:
                lyrics_raw = json.load(f)
            for entry in lyrics_raw:
                lyric_times.append(float(entry["timestamp_ms"]))
                lyric_texts.append(str(entry["text"]))
        self._lyric_times = lyric_times
        self._lyric_texts = lyric_texts

        # Notes: prefer notes.json, otherwise derive from lyrics + pitch track and cache.
        notes_path = os.path.join(self.song_dir(song_id), "notes.json")
        notes: list[Note] = []
        if os.path.isfile(notes_path):
            try:
                with open(notes_path) as f:
                    for entry in json.load(f):
                        notes.append(
                            Note(
                                start_ms=float(entry["start_ms"]),
                                duration_ms=float(entry["duration_ms"]),
                                pitch_hz=float(entry["pitch_hz"]),
                                lyric=str(entry.get("lyric", "")),
                            )
                        )
            except Exception as e:
                print(f"[song_manager] failed to read notes.json ({e}); deriving instead")
                notes = []
        if not notes and lyrics_raw and timestamps:
            notes = derive_notes_from_lyrics(lyrics_raw, timestamps, freqs)
            if notes:
                try:
                    with open(notes_path, "w") as f:
                        json.dump(
                            [
                                {
                                    "start_ms": n.start_ms,
                                    "duration_ms": n.duration_ms,
                                    "pitch_hz": n.pitch_hz,
                                    "lyric": n.lyric,
                                }
                                for n in notes
                            ],
                            f,
                            indent=2,
                        )
                    print(f"[song_manager] wrote {len(notes)} notes to {notes_path}")
                except Exception as e:
                    print(f"[song_manager] failed to write notes.json ({e})")
        self._notes = notes

        self._current_song_id = song_id

    def unload(self) -> None:
        self._current_song_id = None
        self._timestamps = []
        self._freqs = []
        self._lyric_times = []
        self._lyric_texts = []
        self._notes = []

    def get_target_hz(self, position_ms: float) -> float | None:
        if not self._timestamps:
            return None
        idx = bisect.bisect_left(self._timestamps, position_ms)
        # Clamp to valid range
        idx = max(0, min(idx, len(self._timestamps) - 1))
        freq = self._freqs[idx]
        return freq if freq > 0.0 else None

    def get_current_lyric(self, position_ms: float) -> str | None:
        if not self._lyric_times:
            return None
        idx = bisect.bisect_right(self._lyric_times, position_ms) - 1
        if idx < 0:
            return None
        return self._lyric_texts[idx] or None

    def get_notes(self) -> list[Note]:
        return self._notes

    @property
    def current_song_id(self) -> str | None:
        return self._current_song_id


# ---------------------------------------------------------------------------
# Note derivation from lyrics word timings + pitch track
# ---------------------------------------------------------------------------

def derive_notes_from_lyrics(
    lyrics: list[dict],
    pitch_timestamps: list[float],
    pitch_freqs: list[float],
) -> list[Note]:
    """Each lyric word becomes one note. Pitch is the median of voiced
    pitch_track.csv samples falling inside the word's [start, end) window.
    Words with no voiced samples are dropped (rests don't score).

    Note: `pitch_hz` here is metadata only. The scoring engine does
    per-frame comparison against the live `target_hz` from `pitch_track.csv`,
    so multi-pitch (melisma) words are graded against the actual contour, not
    this single median.
    """
    notes: list[Note] = []
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
            voiced = [
                f for f in pitch_freqs[lo:hi] if f > 0.0
            ]
            if not voiced:
                continue
            pitch_hz = statistics.median(voiced)
            notes.append(
                Note(
                    start_ms=start,
                    duration_ms=end - start,
                    pitch_hz=pitch_hz,
                    lyric=str(w.get("text", "")),
                )
            )
    notes.sort(key=lambda n: n.start_ms)
    return notes
