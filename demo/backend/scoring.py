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
PITCH_PERFECT_CENTS = 50.0
PITCH_TOLERANCE_CENTS = 200.0
# Fraction of each note's duration over which pitch frames are scored.
# Defaults to the middle 50% (0.25..0.75) so attack/release transients
# don't drag the average down.
PITCH_SCORE_WINDOW_START = 0.25
PITCH_SCORE_WINDOW_END = 0.75
TIMING_PERFECT_MS = 100.0
TIMING_TOLERANCE_MS = 300.0
W_PITCH = 1
W_TIMING = 0
DURATION_WEIGHT_POWER = 0.5
STAR_THRESHOLDS = (0.25, 0.40, 0.55, 0.70, 0.85)
COMBO_HIT_THRESHOLD = 0.40

# Smoothed pitch quality used by the pulsing border. Tau is the EMA time
# constant; alpha is derived once at module load. Per-tick decay during
# silence pulls the EMA toward zero, then clears to None below the floor.
TICK_S = 0.033
QUALITY_EMA_TAU_S = 0.5
QUALITY_EMA_ALPHA = 1.0 - math.exp(-TICK_S / QUALITY_EMA_TAU_S)
QUALITY_DECAY_FACTOR = 0.95
QUALITY_NULL_THRESHOLD = 0.05

# Octave detection: lock after either bound is reached.
OCTAVE_DETECT_MAX_PAIRS = 64
OCTAVE_DETECT_MAX_MS = 8000.0


Bucket = Literal["hit", "near", "miss"]


@dataclass
class Note:
    start_ms: float
    duration_ms: float
    pitch_hz_candidates: list[float]
    lyric: str = ""

    @property
    def end_ms(self) -> float:
        return self.start_ms + self.duration_ms

    @property
    def pitch_hz(self) -> float:
        return self.pitch_hz_candidates[0]


@dataclass
class NoteResult:
    lyric: str
    pitch_hz: float
    score: float
    pitch_score: float
    timing_score: float
    detected_pitch_hz: float | None = None
    cents_off: float | None = None
    duration_ms: float = 0.0
    onset_offset_ms: float | None = None
    weight: float = 0.0


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
    frame_quality: float | None


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


def trimmed_mean(values: list[float], trim_frac: float = 0.25) -> float:
    """Mean of the middle (1 - 2*trim_frac) of values after sorting.

    Drops outliers from both tails before averaging. With trim_frac=0.25 this
    is the interquartile mean (mean of the middle 50%). Falls back to plain
    mean when there aren't enough samples to trim.
    """
    n = len(values)
    if n == 0:
        return 0.0
    k = int(n * trim_frac)
    if n - 2 * k <= 0:
        return statistics.mean(values)
    s = sorted(values)
    return statistics.mean(s[k : n - k])


def bucket_for(cents: float) -> Bucket:
    a = abs(cents)
    if a <= PITCH_PERFECT_CENTS:
        return "hit"
    if a <= PITCH_TOLERANCE_CENTS:
        return "near"
    return "miss"


def _best_candidate(detected_hz: float, candidates: list[float]) -> float:
    """Pick candidate minimizing |cents_off(detected, c)|."""
    return min(candidates, key=lambda c: abs(cents_off(detected_hz, c)))


class ScoringSession:
    def __init__(self, notes: list[Note]) -> None:
        self._notes = sorted(notes, key=lambda n: n.start_ms)
        self._cursor = 0  # next note index to evaluate

        self._active_idx: int | None = None
        self._active_pitch_scores: list[float] = []
        self._active_detected_hzs: list[float] = []
        self._onset_offset_ms: float | None = None

        self._weighted_score = 0.0
        self._weight_sum = 0.0
        self._combo = 0
        self._best_combo = 0
        self._complete = False

        self._octave_pairs_det: list[float] = []
        self._octave_pairs_tgt: list[float] = []
        self._octave_first_ms: float | None = None
        self._octave_locked = False
        self._octave_shift = 0

        self._quality_ema: float | None = None
        self._last_position_ms: float | None = None

    @property
    def notes(self) -> list[Note]:
        return self._notes

    @property
    def score(self) -> float:
        """Running score normalized to elapsed song progress.

        Includes a partial contribution from the active in-progress note so
        the displayed score (and stars) reflect performance immediately
        rather than starting at 0 until the first note finalizes.
        """
        num = self._weighted_score
        den = self._weight_sum

        if (
            self._active_idx is not None
            and 0 <= self._active_idx < len(self._notes)
            and self._last_position_ms is not None
        ):
            note = self._notes[self._active_idx]
            if note.duration_ms > 0:
                elapsed = max(
                    0.0, min(note.duration_ms, self._last_position_ms - note.start_ms)
                )
                frac = elapsed / note.duration_ms
                if frac > 0:
                    pitch_avg = trimmed_mean(self._active_pitch_scores)
                    timing = (
                        timing_score(self._onset_offset_ms)
                        if self._onset_offset_ms is not None
                        else 0.0
                    )
                    partial_score = W_PITCH * pitch_avg + W_TIMING * timing
                    partial_w = note_weight(note.duration_ms) * frac
                    num += partial_score * partial_w
                    den += partial_w

        if den <= 0:
            return 0.0
        return num / den

    def update(
        self,
        position_ms: float,
        detected_hz: float | None,
        vad_voiced: bool,
    ) -> ScoreState:
        self._last_position_ms = position_ms

        # The "active note" for octave/quality/bucket is the one currently
        # playing under position_ms, regardless of whether the cursor has
        # advanced past it yet this tick. Pick it up front.
        active_note: Note | None = None
        for n in self._notes[self._cursor:]:
            if n.start_ms <= position_ms < n.end_ms:
                active_note = n
                break
            if position_ms < n.start_ms:
                break

        # --- octave detection ---
        if (
            not self._octave_locked
            and vad_voiced
            and detected_hz is not None
            and active_note is not None
        ):
            if self._octave_first_ms is None:
                self._octave_first_ms = position_ms
            best = _best_candidate(detected_hz, active_note.pitch_hz_candidates)
            self._octave_pairs_det.append(detected_hz)
            self._octave_pairs_tgt.append(best)
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
                self._active_detected_hzs = []
                self._onset_offset_ms = None
                self._active_idx = self._cursor
            res = self._finalize_active_note(note)
            if res is not None:
                completed = res  # keep the most recent if multiple in one tick
            self._cursor += 1
            self._active_idx = None
            self._active_pitch_scores = []
            self._active_detected_hzs = []
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
                    self._active_detected_hzs = []
                    self._onset_offset_ms = None

                if (
                    self._onset_offset_ms is None
                    and vad_voiced
                    and detected_hz is not None
                ):
                    self._onset_offset_ms = position_ms - note.start_ms

                score_start = (
                    note.start_ms + PITCH_SCORE_WINDOW_START * note.duration_ms
                )
                score_end = note.start_ms + PITCH_SCORE_WINDOW_END * note.duration_ms
                if (
                    score_start <= position_ms < score_end
                    and vad_voiced
                    and detected_hz is not None
                ):
                    fps = max(
                        frame_pitch_score(cents_off(detected_hz, c))
                        for c in note.pitch_hz_candidates
                    )
                    self._active_pitch_scores.append(fps)
                    self._active_detected_hzs.append(detected_hz)

        # --- frame bucket for color shift ---
        bucket: Bucket | None = None
        if vad_voiced and detected_hz is not None and active_note is not None:
            best = _best_candidate(detected_hz, active_note.pitch_hz_candidates)
            bucket = bucket_for(cents_off(detected_hz, best))

        # --- frame quality EMA (powers the pulsing border on the frontend) ---
        if vad_voiced and detected_hz is not None and active_note is not None:
            fps = max(
                frame_pitch_score(cents_off(detected_hz, c))
                for c in active_note.pitch_hz_candidates
            )
            if self._quality_ema is None:
                self._quality_ema = fps
            else:
                self._quality_ema += QUALITY_EMA_ALPHA * (fps - self._quality_ema)
        elif self._quality_ema is not None:
            self._quality_ema *= QUALITY_DECAY_FACTOR
            if self._quality_ema < QUALITY_NULL_THRESHOLD:
                self._quality_ema = None

        # --- finalize song if all notes consumed ---
        if self._cursor >= len(self._notes) and not self._complete:
            self._complete = True

        target_for_display = (
            active_note.pitch_hz_candidates[0] if active_note is not None else None
        )
        return self._build_state(target_for_display, bucket, completed)

    def finish(self) -> ScoreState:
        """Force-complete the session (e.g. user pressed Stop)."""
        if not self._complete:
            if self._cursor < len(self._notes):
                note = self._notes[self._cursor]
                if self._active_idx != self._cursor:
                    self._active_pitch_scores = []
                    self._active_detected_hzs = []
                    self._onset_offset_ms = None
                    self._active_idx = self._cursor
                self._finalize_active_note(note)
                self._cursor = len(self._notes)
            self._complete = True
        return self._build_state(None, None, None)

    def _finalize_active_note(self, note: Note) -> NoteResult:
        avg = trimmed_mean(self._active_pitch_scores)
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

        detected_median = (
            statistics.median(self._active_detected_hzs)
            if self._active_detected_hzs
            else None
        )
        if detected_median is not None:
            best = _best_candidate(detected_median, note.pitch_hz_candidates)
            cents = cents_off(detected_median, best)
            display_target = best
        else:
            cents = None
            display_target = note.pitch_hz_candidates[0]

        return NoteResult(
            lyric=note.lyric,
            pitch_hz=display_target,
            score=score,
            pitch_score=avg,
            timing_score=t,
            detected_pitch_hz=detected_median,
            cents_off=cents,
            duration_ms=note.duration_ms,
            onset_offset_ms=self._onset_offset_ms,
            weight=w,
        )

    def _build_state(
        self,
        target_hz: float | None,
        bucket: Bucket | None,
        completed: NoteResult | None,
    ) -> ScoreState:
        target_display = (
            target_hz * (2**self._octave_shift) if target_hz is not None else None
        )
        return ScoreState(
            score=self.score,
            combo=self._combo,
            best_combo=self._best_combo,
            target_hz_display=target_display,
            detected_bucket=bucket,
            note_completed=completed,
            stars=stars_for(self.score),
            complete=self._complete,
            frame_quality=self._quality_ema,
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

    print("frame_pitch_score (PERFECT=50, TOL=200):")
    check("0c -> 1.0", frame_pitch_score(0.0) == 1.0)
    check("50c -> 1.0", frame_pitch_score(50.0) == 1.0)
    check("125c -> ~0.5", abs(frame_pitch_score(125.0) - 0.5) < 0.01)
    check("200c -> 0.0", frame_pitch_score(200.0) == 0.0)

    print("timing_score:")
    check("0ms -> 1.0", timing_score(0.0) == 1.0)
    check("300ms -> 0.0", timing_score(300.0) == 0.0)

    print("stars_for (thresholds 0.25, 0.40, 0.55, 0.70, 0.85):")
    check("0.24 -> 0", stars_for(0.24) == 0)
    check("0.25 -> 1", stars_for(0.25) == 1)
    check("0.55 -> 3", stars_for(0.55) == 3)
    check("0.84 -> 4", stars_for(0.84) == 4)
    check("0.85 -> 5", stars_for(0.85) == 5)

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
        Note(start_ms=0, duration_ms=500, pitch_hz_candidates=[440.0], lyric="a"),
        Note(start_ms=500, duration_ms=500, pitch_hz_candidates=[494.0], lyric="b"),
        Note(start_ms=1000, duration_ms=500, pitch_hz_candidates=[523.25], lyric="c"),
    ]
    sess = ScoringSession(notes)
    completed_results: list[NoteResult] = []
    t = 0.0
    while t < 1600:
        target = None
        for n in notes:
            if n.start_ms <= t < n.end_ms:
                target = n.pitch_hz
                break
        state = sess.update(t, target, vad_voiced=target is not None)
        if state.note_completed is not None:
            completed_results.append(state.note_completed)
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
    check(
        "captured one NoteResult per note",
        len(completed_results) == len(notes),
        f"got {len(completed_results)}",
    )
    for i, (note, nr) in enumerate(zip(notes, completed_results)):
        check(
            f"note[{i}] detected_pitch_hz ≈ target",
            nr.detected_pitch_hz is not None
            and abs(nr.detected_pitch_hz - note.pitch_hz) < 1e-6,
            f"detected={nr.detected_pitch_hz}",
        )
        check(
            f"note[{i}] |cents_off| < 1",
            nr.cents_off is not None and abs(nr.cents_off) < 1.0,
            f"cents_off={nr.cents_off}",
        )

    print("ScoringSession (silence run -> 0):")
    sess2 = ScoringSession(notes)
    silent_results: list[NoteResult] = []
    t = 0.0
    while t < 1600:
        state2 = sess2.update(t, None, vad_voiced=False)
        if state2.note_completed is not None:
            silent_results.append(state2.note_completed)
        t += 33.0
    final2 = sess2.finish()
    check("silence score == 0.0", final2.score == 0.0)
    check("silence stars == 0", final2.stars == 0)
    check("silence frame_quality is None", final2.frame_quality is None)
    check(
        "silence: detected_pitch_hz is None for every note",
        all(nr.detected_pitch_hz is None for nr in silent_results),
    )
    check(
        "silence: cents_off is None for every note",
        all(nr.cents_off is None for nr in silent_results),
    )

    print(
        "ScoringSession (voiced phrase then silence -> frame_quality decays to None):"
    )
    sess3 = ScoringSession(
        [Note(start_ms=0, duration_ms=1000, pitch_hz_candidates=[440.0], lyric="x")]
    )
    t = 0.0
    # 1 s voiced
    while t < 1000:
        sess3.update(t, 440.0, vad_voiced=True)
        t += 33.0
    mid = sess3.update(999.0, 440.0, vad_voiced=True)
    check(
        "frame_quality high after voiced phrase",
        mid.frame_quality is not None and mid.frame_quality >= 0.99,
        f"frame_quality={mid.frame_quality}",
    )
    sess3.update(1000.0, 440.0, vad_voiced=True)  # advance cursor past note
    # 2 s silence
    last_silence: ScoreState | None = None
    while t < 3000:
        last_silence = sess3.update(t, None, vad_voiced=False)
        t += 33.0
    assert last_silence is not None
    check(
        "frame_quality decays to None after 2 s silence",
        last_silence.frame_quality is None,
        f"frame_quality={last_silence.frame_quality}",
    )

    print("ScoringSession (multi-candidate generosity):")

    def _run_constant_pitch(candidates: list[float], detected: float) -> float:
        sess_mc = ScoringSession(
            [
                Note(
                    start_ms=0,
                    duration_ms=500,
                    pitch_hz_candidates=candidates,
                    lyric="m",
                )
            ]
        )
        t_mc = 0.0
        while t_mc < 600:
            sess_mc.update(t_mc, detected, vad_voiced=True)
            t_mc += 33.0
        return sess_mc.finish().score

    score_a = _run_constant_pitch([440.0, 494.0], 440.0)
    score_b = _run_constant_pitch([440.0, 494.0], 494.0)
    score_mid = _run_constant_pitch([440.0, 494.0], 466.16)
    check("singer hits low candidate -> 1.0", abs(score_a - 1.0) < 1e-3, f"{score_a:.3f}")
    check("singer hits high candidate -> 1.0", abs(score_b - 1.0) < 1e-3, f"{score_b:.3f}")
    check(
        "singer between candidates -> partial",
        0.3 < score_mid < 0.7,
        f"{score_mid:.3f}",
    )

    sys.exit(0 if failures == 0 else 1)
