"""Karaoke scoring engine for sing-along mode.

Pitch-class (octave-agnostic) scoring against a list of target notes.
Plan: ~/.claude/plans/i-want-to-add-async-lagoon.md
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass
from typing import Literal

# ---------- tunables ----------
PITCH_PERFECT_CENTS = 20.0
PITCH_TOLERANCE_CENTS = 80.0
TIMING_PERFECT_MS = 100.0
TIMING_TOLERANCE_MS = 300.0
W_PITCH = 0.75
W_TIMING = 0.25
DURATION_WEIGHT_POWER = 0.5
STAR_THRESHOLDS = (0.40, 0.55, 0.70, 0.82, 0.92)
COMBO_HIT_THRESHOLD = 0.60

# Octave detection: lock after either bound is reached.
OCTAVE_DETECT_MAX_PAIRS = 64
OCTAVE_DETECT_MAX_MS = 8000.0


Bucket = Literal["hit", "near", "miss"]


@dataclass
class Note:
    start_ms: float
    duration_ms: float
    pitch_hz: float
    lyric: str = ""

    @property
    def end_ms(self) -> float:
        return self.start_ms + self.duration_ms


@dataclass
class NoteResult:
    lyric: str
    pitch_hz: float
    score: float
    pitch_score: float
    timing_score: float


@dataclass
class ScoreState:
    score: float
    combo: int
    best_combo: int
    target_hz_display: float | None
    detected_bucket: Bucket | None
    note_completed: NoteResult | None
    stars: int
    complete: bool


def hz_to_midi(hz: float) -> float:
    return 12.0 * math.log2(hz / 440.0) + 69.0


def cents_off(detected_hz: float, target_hz: float) -> float:
    """Pitch-class distance in cents, folded to (-600, 600]."""
    diff_semi = hz_to_midi(detected_hz) - hz_to_midi(target_hz)
    folded = ((diff_semi + 6.0) % 12.0) - 6.0
    return folded * 100.0


def _falloff(value: float, perfect: float, tolerance: float) -> float:
    v = abs(value)
    if v <= perfect:
        return 1.0
    if v >= tolerance:
        return 0.0
    return 1.0 - (v - perfect) / (tolerance - perfect)


def frame_pitch_score(cents: float) -> float:
    return _falloff(cents, PITCH_PERFECT_CENTS, PITCH_TOLERANCE_CENTS)


def timing_score(onset_offset_ms: float) -> float:
    return _falloff(onset_offset_ms, TIMING_PERFECT_MS, TIMING_TOLERANCE_MS)


def note_weight(duration_ms: float) -> float:
    return max(duration_ms / 1000.0, 0.0) ** DURATION_WEIGHT_POWER


def stars_for(score: float) -> int:
    n = 0
    for thresh in STAR_THRESHOLDS:
        if score >= thresh:
            n += 1
    return n


def octave_shift_for(detected_hz: list[float], target_hz: list[float]) -> int:
    """Pick k in [-2..2] such that target * 2^k best aligns with detected.

    Equivalent to minimizing median |midi(detected) - (midi(target) + 12k)|.
    """
    if not detected_hz or not target_hz or len(detected_hz) != len(target_hz):
        return 0
    det_midi = [hz_to_midi(h) for h in detected_hz]
    tgt_midi = [hz_to_midi(h) for h in target_hz]
    best_k = 0
    best_err = math.inf
    for k in range(-2, 3):
        diffs = [abs(d - (t + 12 * k)) for d, t in zip(det_midi, tgt_midi)]
        err = statistics.median(diffs)
        if err < best_err:
            best_err = err
            best_k = k
    return best_k


def bucket_for(cents: float) -> Bucket:
    a = abs(cents)
    if a <= PITCH_PERFECT_CENTS:
        return "hit"
    if a <= PITCH_TOLERANCE_CENTS:
        return "near"
    return "miss"


class ScoringSession:
    def __init__(self, notes: list[Note]) -> None:
        self._notes = sorted(notes, key=lambda n: n.start_ms)
        self._cursor = 0  # next note index to evaluate

        self._active_idx: int | None = None
        self._active_pitch_scores: list[float] = []
        self._onset_offset_ms: float | None = None

        self._weighted_score = 0.0
        self._weight_sum = 0.0
        self._combo = 0
        self._best_combo = 0
        self._stars = 0
        self._complete = False

        self._octave_pairs_det: list[float] = []
        self._octave_pairs_tgt: list[float] = []
        self._octave_first_ms: float | None = None
        self._octave_locked = False
        self._octave_shift = 0

    @property
    def notes(self) -> list[Note]:
        return self._notes

    @property
    def score(self) -> float:
        if self._weight_sum <= 0:
            return 0.0
        return self._weighted_score / self._weight_sum

    def update(
        self,
        position_ms: float,
        detected_hz: float | None,
        target_hz: float | None,
        vad_voiced: bool,
    ) -> ScoreState:
        if self._complete:
            return self._build_state(target_hz, None, None)

        # --- octave detection ---
        if (
            not self._octave_locked
            and vad_voiced
            and detected_hz is not None
            and target_hz is not None
        ):
            if self._octave_first_ms is None:
                self._octave_first_ms = position_ms
            self._octave_pairs_det.append(detected_hz)
            self._octave_pairs_tgt.append(target_hz)
            elapsed = position_ms - self._octave_first_ms
            if (
                len(self._octave_pairs_det) >= OCTAVE_DETECT_MAX_PAIRS
                or elapsed >= OCTAVE_DETECT_MAX_MS
            ):
                self._octave_shift = octave_shift_for(
                    self._octave_pairs_det, self._octave_pairs_tgt
                )
                self._octave_locked = True

        # --- advance cursor through any notes whose end has been reached ---
        completed: NoteResult | None = None
        while self._cursor < len(self._notes):
            note = self._notes[self._cursor]
            if position_ms < note.end_ms:
                break
            if self._active_idx != self._cursor:
                # We never entered this note; finalize it as a zero-score skip.
                self._active_pitch_scores = []
                self._onset_offset_ms = None
                self._active_idx = self._cursor
            res = self._finalize_active_note(note)
            if res is not None:
                completed = res  # keep the most recent if multiple in one tick
            self._cursor += 1
            self._active_idx = None
            self._active_pitch_scores = []
            self._onset_offset_ms = None

        # --- accumulate into the current active note ---
        if self._cursor < len(self._notes):
            note = self._notes[self._cursor]
            in_onset_window = (
                note.start_ms - TIMING_TOLERANCE_MS <= position_ms < note.end_ms
            )
            if in_onset_window:
                if self._active_idx != self._cursor:
                    self._active_idx = self._cursor
                    self._active_pitch_scores = []
                    self._onset_offset_ms = None

                if (
                    self._onset_offset_ms is None
                    and vad_voiced
                    and detected_hz is not None
                ):
                    self._onset_offset_ms = position_ms - note.start_ms

                if (
                    note.start_ms <= position_ms < note.end_ms
                    and vad_voiced
                    and detected_hz is not None
                    and target_hz is not None
                ):
                    self._active_pitch_scores.append(
                        frame_pitch_score(cents_off(detected_hz, target_hz))
                    )

        # --- frame bucket for color shift ---
        bucket: Bucket | None = None
        if vad_voiced and detected_hz is not None and target_hz is not None:
            bucket = bucket_for(cents_off(detected_hz, target_hz))

        # --- finalize song if all notes consumed ---
        if self._cursor >= len(self._notes) and not self._complete:
            self._complete = True
            self._stars = stars_for(self.score)

        return self._build_state(target_hz, bucket, completed)

    def finish(self) -> ScoreState:
        """Force-complete the session (e.g. user pressed Stop)."""
        if not self._complete:
            if self._cursor < len(self._notes):
                note = self._notes[self._cursor]
                if self._active_idx != self._cursor:
                    self._active_pitch_scores = []
                    self._onset_offset_ms = None
                    self._active_idx = self._cursor
                self._finalize_active_note(note)
                self._cursor = len(self._notes)
            self._complete = True
            self._stars = stars_for(self.score)
        return self._build_state(None, None, None)

    def _finalize_active_note(self, note: Note) -> NoteResult:
        avg = (
            statistics.mean(self._active_pitch_scores)
            if self._active_pitch_scores
            else 0.0
        )
        onset = (
            self._onset_offset_ms
            if self._onset_offset_ms is not None
            else (TIMING_TOLERANCE_MS + 1.0)
        )
        t = timing_score(onset)
        score = W_PITCH * avg + W_TIMING * t
        w = note_weight(note.duration_ms)
        self._weighted_score += score * w
        self._weight_sum += w

        if score >= COMBO_HIT_THRESHOLD:
            self._combo += 1
            self._best_combo = max(self._best_combo, self._combo)
        else:
            self._combo = 0

        return NoteResult(
            lyric=note.lyric,
            pitch_hz=note.pitch_hz,
            score=score,
            pitch_score=avg,
            timing_score=t,
        )

    def _build_state(
        self,
        target_hz: float | None,
        bucket: Bucket | None,
        completed: NoteResult | None,
    ) -> ScoreState:
        target_display = (
            target_hz * (2 ** self._octave_shift) if target_hz is not None else None
        )
        return ScoreState(
            score=self.score,
            combo=self._combo,
            best_combo=self._best_combo,
            target_hz_display=target_display,
            detected_bucket=bucket,
            note_completed=completed,
            stars=self._stars,
            complete=self._complete,
        )


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import sys

    failures = 0

    def check(label: str, ok: bool, info: str = "") -> None:
        global failures
        mark = "OK" if ok else "FAIL"
        suffix = f" — {info}" if info else ""
        print(f"  [{mark}] {label}{suffix}")
        if not ok:
            failures += 1

    print("cents_off:")
    check("identical -> 0", abs(cents_off(440.0, 440.0)) < 1e-6)
    check("octave-agnostic 880↔440 -> 0", abs(cents_off(880.0, 440.0)) < 1e-6)
    check("octave-agnostic 220↔440 -> 0", abs(cents_off(220.0, 440.0)) < 1e-6)
    check(
        "440↔466.16 ≈ -100c",
        abs(cents_off(440.0, 466.16) + 100.0) < 2.0,
        f"{cents_off(440.0, 466.16):.2f}",
    )

    print("frame_pitch_score:")
    check("0c -> 1.0", frame_pitch_score(0.0) == 1.0)
    check("80c -> 0.0", frame_pitch_score(80.0) == 0.0)
    check("50c -> ~0.5", abs(frame_pitch_score(50.0) - 0.5) < 0.01)

    print("timing_score:")
    check("0ms -> 1.0", timing_score(0.0) == 1.0)
    check("300ms -> 0.0", timing_score(300.0) == 0.0)

    print("stars_for:")
    check("0.39 -> 0", stars_for(0.39) == 0)
    check("0.40 -> 1", stars_for(0.40) == 1)
    check("0.91 -> 4", stars_for(0.91) == 4)
    check("0.92 -> 5", stars_for(0.92) == 5)

    print("octave_shift_for:")
    check(
        "220 vs 440 -> -1 (target/2 to match singer)",
        octave_shift_for([220.0] * 30, [440.0] * 30) == -1,
    )
    check(
        "880 vs 440 -> +1 (target*2 to match singer)",
        octave_shift_for([880.0] * 30, [440.0] * 30) == 1,
    )
    check(
        "440 vs 440 -> 0",
        octave_shift_for([440.0] * 30, [440.0] * 30) == 0,
    )

    print("ScoringSession (synthetic perfect run):")
    notes = [
        Note(start_ms=0, duration_ms=500, pitch_hz=440.0, lyric="a"),
        Note(start_ms=500, duration_ms=500, pitch_hz=494.0, lyric="b"),
        Note(start_ms=1000, duration_ms=500, pitch_hz=523.25, lyric="c"),
    ]
    sess = ScoringSession(notes)
    t = 0.0
    while t < 1600:
        target = None
        for n in notes:
            if n.start_ms <= t < n.end_ms:
                target = n.pitch_hz
                break
        sess.update(t, target, target, vad_voiced=target is not None)
        t += 33.0
    final = sess.finish()
    check("complete", final.complete)
    check(
        "score == 1.0",
        abs(final.score - 1.0) < 1e-3,
        f"score={final.score:.3f}",
    )
    check("stars == 5", final.stars == 5)
    check(
        "best_combo == len(notes)",
        final.best_combo == len(notes),
        f"best_combo={final.best_combo}",
    )

    print("ScoringSession (silence run -> 0):")
    sess2 = ScoringSession(notes)
    t = 0.0
    while t < 1600:
        sess2.update(t, None, None, vad_voiced=False)
        t += 33.0
    final2 = sess2.finish()
    check("silence score == 0.0", final2.score == 0.0)
    check("silence stars == 0", final2.stars == 0)

    sys.exit(0 if failures == 0 else 1)
