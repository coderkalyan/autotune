import bisect
import csv
import json
import os


class SongManager:
    def __init__(self, songs_dir: str) -> None:
        self._songs_dir = os.path.abspath(songs_dir)
        self._current_song_id: str | None = None
        self._timestamps: list[float] = []
        self._freqs: list[float] = []

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

    def instrumental_path(self, song_id: str) -> str:
        return os.path.join(self.song_dir(song_id), "instrumental.wav")

    def cover_path(self, song_id: str) -> str:
        return os.path.join(self.song_dir(song_id), "cover.jpg")

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
        self._current_song_id = song_id

    def unload(self) -> None:
        self._current_song_id = None
        self._timestamps = []
        self._freqs = []

    def get_target_hz(self, position_ms: float) -> float | None:
        if not self._timestamps:
            return None
        idx = bisect.bisect_left(self._timestamps, position_ms)
        # Clamp to valid range
        idx = max(0, min(idx, len(self._timestamps) - 1))
        freq = self._freqs[idx]
        return freq if freq > 0.0 else None

    @property
    def current_song_id(self) -> str | None:
        return self._current_song_id
