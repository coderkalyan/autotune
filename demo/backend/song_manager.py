import bisect
import json
import math
import os

from pitch_utils import midi_to_hz
from scoring import Note


class SongManager:
    def __init__(self, songs_dir: str) -> None:
        self._songs_dir = os.path.abspath(songs_dir)
        self._current_song_id: str | None = None
        self._lyric_times: list[float] = []
        self._lyric_texts: list[str] = []
        self._notes: list[Note] = []
        self._note_starts: list[float] = []

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
                    "grade_start_ms": meta.get("grade_start_ms", 0),
                    "grade_end_ms": meta.get("grade_end_ms", 0),
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

        # Notes: prefer notes.json (v2 schema with pitch_hz_candidates), otherwise
        # derive from lyrics' MIDI notes and cache.
        notes_path = os.path.join(self.song_dir(song_id), "notes.json")
        notes: list[Note] = []
        if os.path.isfile(notes_path):
            try:
                with open(notes_path) as f:
                    cached = json.load(f)
                if all("pitch_hz_candidates" in entry for entry in cached):
                    for entry in cached:
                        notes.append(
                            Note(
                                start_ms=float(entry["start_ms"]),
                                duration_ms=float(entry["duration_ms"]),
                                pitch_hz_candidates=[
                                    float(c) for c in entry["pitch_hz_candidates"]
                                ],
                                lyric=str(entry.get("lyric", "")),
                            )
                        )
                else:
                    print(
                        f"[song_manager] notes.json at {notes_path} is stale (missing"
                        " pitch_hz_candidates); re-deriving"
                    )
            except Exception as e:
                print(f"[song_manager] failed to read notes.json ({e}); deriving instead")
                notes = []
        if not notes and lyrics_raw:
            notes = derive_notes_from_lyrics(lyrics_raw)
            if notes:
                try:
                    with open(notes_path, "w") as f:
                        json.dump(
                            [
                                {
                                    "start_ms": n.start_ms,
                                    "duration_ms": n.duration_ms,
                                    "pitch_hz_candidates": n.pitch_hz_candidates,
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
        self._note_starts = [n.start_ms for n in notes]

        self._current_song_id = song_id

    def unload(self) -> None:
        self._current_song_id = None
        self._lyric_times = []
        self._lyric_texts = []
        self._notes = []
        self._note_starts = []

    def get_target_hz(self, position_ms: float) -> float | None:
        if not self._notes:
            return None
        idx = bisect.bisect_right(self._note_starts, position_ms) - 1
        if idx < 0:
            return None
        note = self._notes[idx]
        if position_ms >= note.end_ms:
            return None
        return note.pitch_hz_candidates[0]

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

def derive_notes_from_lyrics(lyrics: list[dict]) -> list[Note]:
    """Each lyric word becomes one scoring Note. Targets come from the word's
    `note` field, which is either a single MIDI int or a list of MIDI ints
    (melisma). Each MIDI value is converted to Hz; the scoring engine then
    grades each frame against the closest candidate (per-frame max).

    Words missing a `note` field, or with empty/non-numeric notes, are skipped.
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
            raw = w.get("note")
            if raw is None:
                continue
            midis = raw if isinstance(raw, list) else [raw]
            candidates: list[float] = []
            for m in midis:
                try:
                    hz = midi_to_hz(float(m))
                except (TypeError, ValueError):
                    continue
                if math.isfinite(hz) and hz > 0.0:
                    candidates.append(hz)
            if not candidates:
                continue
            notes.append(
                Note(
                    start_ms=start,
                    duration_ms=end - start,
                    pitch_hz_candidates=candidates,
                    lyric=str(w.get("text", "")),
                )
            )
    notes.sort(key=lambda n: n.start_ms)
    return notes
