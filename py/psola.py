from dataclasses import dataclass
import os
import sys

import matplotlib

# Prefer interactive plots, but fall back to PNG when running headless.
if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
    matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

from autocorrelation import autocorrelation, peak, pcm_waveform


# NOTE: for debugging we use pcm_waveform() from autocorrelation.py.
# If you ever want a full-file pass, you can uncomment this reader.
# def read_pcm_f32(path: str) -> np.ndarray:
#     with open(path, "rb") as f:
#         buf = f.read()
#     return np.frombuffer(buf, dtype=np.float32).copy()


def write_pcm_f32(path: str, x: np.ndarray) -> None:
    """Write raw float32 PCM (mono) from a 1-D numpy array."""
    x = np.asarray(x, dtype=np.float32)
    with open(path, "wb") as f:
        f.write(x.tobytes())


@dataclass
class F0Estimate:
    f0_hz: float
    period_samples: int


def estimate_f0_autocorr(
    x: np.ndarray,
    fs_hz: int,
    *,
    window_size: int = 1024,
    stride: int = 256,
    fmin_hz: float = 60.0,
    fmax_hz: float = 800.0,
    analysis_seconds: float = 0.5,
    max_frames: int = 80,
) -> F0Estimate | None:
    """Estimate a single (global) f0 for TD-PSOLA using autocorrelation peak-picking.

    NOTE: the provided autocorrelation implementation is O(N^2) per frame.
    To keep this usable on long files, we only analyze a short prefix and cap
    the number of analyzed frames.
    """
    x = np.asarray(x, dtype=np.float64)
    if x.ndim != 1 or len(x) < window_size:
        return None

    min_period = int(fs_hz / fmax_hz)
    max_period = int(fs_hz / fmin_hz)
    if max_period <= 0 or max_period >= window_size:
        return None

    mx = float(np.max(np.abs(x)))
    if mx == 0.0:
        return None

    # Try to avoid analyzing initial silence.
    thr = max(1e-4, 0.01 * mx)
    nz = np.flatnonzero(np.abs(x) > thr)
    start0 = int(max(0, (nz[0] - window_size // 2))) if len(nz) else 0

    analysis_N = int(min(len(x), start0 + max(window_size, analysis_seconds * fs_hz)))
    starts = list(range(start0, analysis_N - window_size + 1, stride))
    if not starts:
        return None

    if max_frames is not None and len(starts) > max_frames:
        idx = np.linspace(0, len(starts) - 1, max_frames, dtype=int)
        starts = [starts[i] for i in idx]

    win = np.hanning(window_size)
    f0s: list[float] = []
    for start in starts:
        frame = x[start : start + window_size]
        frame = (frame - np.mean(frame)) * win
        r = autocorrelation(frame)
        max_lag = min(len(r), max_period)

        p = peak(r, max_lag)
        if p is None or p < min_period:
            # Fallback: pick the strongest lag in-range if it has reasonable strength.
            lo = min_period
            hi = max_lag
            if hi > lo + 1:
                rr = r[lo:hi]
                k = int(np.argmax(rr))
                p2 = lo + k
                if r[p2] > 0.2 * r[0]:
                    p = p2

        if p is None or p < min_period:
            continue
        f0s.append(fs_hz / p)

    if not f0s:
        return None

    f0_hz = float(np.median(f0s))
    period = int(round(fs_hz / f0_hz))
    if period <= 0:
        return None
    return F0Estimate(f0_hz=f0_hz, period_samples=period)


def estimate_f0_contour_autocorr(
    x: np.ndarray,
    fs_hz: int,
    *,
    window_size: int = 1024,
    hop: int = 256,
    fmin_hz: float = 60.0,
    fmax_hz: float = 800.0,
    strength_thresh: float = 0.2,
) -> tuple[np.ndarray, np.ndarray]:
    """Estimate an f0 contour f0[t] using autocorrelation peak picking.

    Returns (frame_starts_samples, f0_hz_per_frame). Unvoiced frames are 0.

    Warning: this calls the O(N^2) autocorrelation per-frame; keep segments short
    (use --start-s/--end-s) or increase hop for long files.
    """
    x = np.asarray(x, dtype=np.float64)
    if x.ndim != 1 or len(x) < window_size:
        return np.array([], dtype=np.int64), np.array([], dtype=np.float64)

    min_period = int(fs_hz / fmax_hz)
    max_period = int(fs_hz / fmin_hz)
    if max_period <= 0 or max_period >= window_size:
        return np.array([], dtype=np.int64), np.array([], dtype=np.float64)

    win = np.hanning(window_size)
    starts = np.arange(0, len(x) - window_size + 1, hop, dtype=np.int64)
    f0s = np.zeros(len(starts), dtype=np.float64)

    mx = float(np.max(np.abs(x)))
    thr = max(1e-4, 0.01 * mx) if mx > 0 else 0.0

    for i, start in enumerate(starts):
        frame = x[start : start + window_size]
        if thr > 0 and float(np.max(np.abs(frame))) < thr:
            continue

        frame = (frame - np.mean(frame)) * win
        r = autocorrelation(frame)
        max_lag = min(len(r), max_period)

        p = peak(r, max_lag)
        if p is None or p < min_period:
            lo = min_period
            hi = max_lag
            if hi > lo + 1:
                rr = r[lo:hi]
                k = int(np.argmax(rr))
                p2 = lo + k
                if r[p2] > strength_thresh * r[0]:
                    p = p2

        if p is None or p < min_period or r[0] == 0:
            continue

        if r[p] / r[0] < strength_thresh:
            continue

        f0s[i] = fs_hz / p

    return starts, f0s


def _pitch_marks_from_period(x: np.ndarray, period: int) -> np.ndarray:
    """Generate crude pitch marks every ~period samples, snapping to nearby peaks."""
    x = np.asarray(x)
    N = len(x)
    if period < 2 or N < 3 * period:
        return np.array([], dtype=np.int64)

    marks: list[int] = []
    hop = period
    search = max(1, period // 2)

    n = period
    while n < N - period:
        lo = max(0, n - search)
        hi = min(N, n + search + 1)
        # Snap to a prominent excitation-like point.
        k = lo + int(np.argmax(np.abs(x[lo:hi])))
        marks.append(k)
        n += hop

    return np.asarray(marks, dtype=np.int64)


def td_psola_pitch_shift(
    x: np.ndarray,
    fs_hz: int,
    *,
    ratio: float,
    f0_window_size: int = 1024,
    f0_stride: int = 256,
    f0_analysis_seconds: float = 0.5,
    f0_max_frames: int = 80,
    fmin_hz: float = 60.0,
    fmax_hz: float = 800.0,
) -> tuple[np.ndarray, dict]:
    """Very small TD-PSOLA pitch shifter (mono) using a single global f0 estimate.

    This is intended as a prototype:
    - global f0 (median over frames)
    - simple peak-snapped pitch marks
    - overlap-add of 2*P windows

    Returns: (y, debug_dict)
    """
    if ratio <= 0:
        raise ValueError("ratio must be > 0")

    x = np.asarray(x, dtype=np.float64)
    N = len(x)
    if x.ndim != 1 or N == 0:
        raise ValueError("x must be a non-empty 1-D array")

    est = estimate_f0_autocorr(
        x,
        fs_hz,
        window_size=f0_window_size,
        stride=f0_stride,
        analysis_seconds=f0_analysis_seconds,
        max_frames=f0_max_frames,
        fmin_hz=fmin_hz,
        fmax_hz=fmax_hz,
    )
    if est is None:
        # Fallback: no pitch detected; return passthrough.
        return x.astype(np.float32), {"f0_hz": None, "period": None}

    P = est.period_samples
    P_syn = int(round(P / ratio))
    P_syn = max(2, P_syn)

    analysis_marks = _pitch_marks_from_period(x, P)
    if len(analysis_marks) < 2:
        return x.astype(np.float32), {"f0_hz": est.f0_hz, "period": P}

    # Synthesis marks: place marks uniformly at the desired period.
    # (Do NOT snap to input peaks; that tends to break the shift audibly.)
    start_mark = int(analysis_marks[0])
    synth_marks = np.arange(start_mark, N - 1, P_syn, dtype=np.int64)
    if len(synth_marks) < 2:
        return x.astype(np.float32), {"f0_hz": est.f0_hz, "period": P}

    # Old/debug option (kept for reference):
    # synth_marks = _pitch_marks_from_period(x, P_syn)

    win_len = 2 * P
    win = np.hanning(win_len)

    y = np.zeros(N, dtype=np.float64)
    wsum = np.zeros(N, dtype=np.float64)

    # Map each synthesis mark to the nearest analysis mark (same time axis).
    # Using searchsorted keeps this simple and fast.
    for sm in synth_marks:
        j = int(np.searchsorted(analysis_marks, sm))
        if j <= 0:
            am = int(analysis_marks[0])
        elif j >= len(analysis_marks):
            am = int(analysis_marks[-1])
        else:
            left = int(analysis_marks[j - 1])
            right = int(analysis_marks[j])
            am = left if (sm - left) <= (right - sm) else right

        a0 = am - P
        a1 = am + P
        s0 = sm - P
        s1 = sm + P

        # Clip to bounds; keep analysis/synthesis ranges aligned.
        if a0 < 0:
            shift = -a0
            a0 = 0
            s0 += shift
        if s0 < 0:
            shift = -s0
            s0 = 0
            a0 += shift
        if a1 > N:
            shift = a1 - N
            a1 = N
            s1 -= shift
        if s1 > N:
            shift = s1 - N
            s1 = N
            a1 -= shift

        L = min(a1 - a0, s1 - s0)
        if L <= 4:
            continue

        seg = x[a0 : a0 + L]
        w = win[(a0 - (am - P)) : (a0 - (am - P)) + L]

        y[s0 : s0 + L] += seg * w
        wsum[s0 : s0 + L] += w

    # Normalize overlap-add; for uncovered samples, fall back to original.
    eps = 1e-8
    covered = wsum > eps
    y_out = x.copy()
    y_out[covered] = y[covered] / wsum[covered]

    # Light amplitude safety.
    max_abs = float(np.max(np.abs(y_out))) if len(y_out) else 0.0
    if max_abs > 1.0:
        y_out = y_out / max_abs

    debug = {
        "mode": "global",
        "f0_hz": est.f0_hz,
        "period": P,
        "period_syn": P_syn,
        "num_analysis_marks": int(len(analysis_marks)),
        "num_synth_marks": int(len(synth_marks)),
    }
    return y_out.astype(np.float32), debug


def td_psola_pitch_shift_contour(
    x: np.ndarray,
    fs_hz: int,
    *,
    ratio: float,
    f0_window_size: int = 1024,
    f0_hop: int = 256,
    fmin_hz: float = 60.0,
    fmax_hz: float = 800.0,
) -> tuple[np.ndarray, dict]:
    """TD-PSOLA pitch shifter using a time-varying f0 contour (input×ratio target)."""
    if ratio <= 0:
        raise ValueError("ratio must be > 0")

    x = np.asarray(x, dtype=np.float64)
    N = len(x)
    if x.ndim != 1 or N == 0:
        raise ValueError("x must be a non-empty 1-D array")

    starts, f0s = estimate_f0_contour_autocorr(
        x,
        fs_hz,
        window_size=f0_window_size,
        hop=f0_hop,
        fmin_hz=fmin_hz,
        fmax_hz=fmax_hz,
    )
    if len(starts) == 0:
        return x.astype(np.float32), {"mode": "contour", "reason": "no-frames"}

    # Period tracks (0 => unvoiced)
    periods_in = np.zeros_like(f0s, dtype=np.int64)
    voiced = f0s > 0
    periods_in[voiced] = np.maximum(2, np.round(fs_hz / f0s[voiced]).astype(np.int64))

    periods_tgt = np.zeros_like(periods_in)
    periods_tgt[voiced] = np.maximum(2, np.round(periods_in[voiced] / ratio).astype(np.int64))

    def period_at(n: int, periods: np.ndarray) -> int:
        i = int(min(len(periods) - 1, max(0, n // f0_hop)))
        return int(periods[i])

    # Analysis marks: walk forward using the local input period, snapping to peaks.
    analysis_marks: list[int] = []
    n = 0
    while n < N:
        P = period_at(n, periods_in)
        if P <= 1:
            n += f0_hop
            continue
        search = max(1, P // 2)
        lo = max(0, n - search)
        hi = min(N, n + search + 1)
        k = lo + int(np.argmax(np.abs(x[lo:hi])))
        analysis_marks.append(k)
        n = k + P

    analysis_marks = np.asarray(analysis_marks, dtype=np.int64)
    if len(analysis_marks) < 2:
        return x.astype(np.float32), {"mode": "contour", "reason": "no-marks"}

    # Synthesis marks: walk forward using the local target period (no snapping).
    synth_marks: list[int] = []
    n = int(analysis_marks[0])
    while n < N:
        P = period_at(n, periods_tgt)
        if P <= 1:
            n += f0_hop
            continue
        synth_marks.append(n)
        n += P

    synth_marks = np.asarray(synth_marks, dtype=np.int64)
    if len(synth_marks) < 2:
        return x.astype(np.float32), {"mode": "contour", "reason": "no-synth"}

    y = np.zeros(N, dtype=np.float64)
    wsum = np.zeros(N, dtype=np.float64)

    for sm in synth_marks:
        j = int(np.searchsorted(analysis_marks, sm))
        if j <= 0:
            am = int(analysis_marks[0])
        elif j >= len(analysis_marks):
            am = int(analysis_marks[-1])
        else:
            left = int(analysis_marks[j - 1])
            right = int(analysis_marks[j])
            am = left if (sm - left) <= (right - sm) else right

        P = period_at(am, periods_in)
        if P <= 1:
            continue

        win = np.hanning(2 * P)
        a0, a1 = am - P, am + P
        s0, s1 = sm - P, sm + P

        if a0 < 0:
            shift = -a0
            a0 = 0
            s0 += shift
        if s0 < 0:
            shift = -s0
            s0 = 0
            a0 += shift
        if a1 > N:
            shift = a1 - N
            a1 = N
            s1 -= shift
        if s1 > N:
            shift = s1 - N
            s1 = N
            a1 -= shift

        L = min(a1 - a0, s1 - s0)
        if L <= 4:
            continue

        seg = x[a0 : a0 + L]
        w = win[(a0 - (am - P)) : (a0 - (am - P)) + L]
        y[s0 : s0 + L] += seg * w
        wsum[s0 : s0 + L] += w

    eps = 1e-8
    covered = wsum > eps
    y_out = x.copy()
    y_out[covered] = y[covered] / wsum[covered]

    max_abs = float(np.max(np.abs(y_out))) if len(y_out) else 0.0
    if max_abs > 1.0:
        y_out = y_out / max_abs

    debug = {
        "mode": "contour",
        "num_frames": int(len(f0s)),
        "voiced_frames": int(np.count_nonzero(voiced)),
        "num_analysis_marks": int(len(analysis_marks)),
        "num_synth_marks": int(len(synth_marks)),
    }
    return y_out.astype(np.float32), debug


def _debug_time_window(path: str) -> tuple[float, float]:
    # These are lifted from autocorrelation.py examples (real audio regions),
    # but widened so the f0 window (1024 samples) fits.
    if "twinkle" in path:
        return 5.00, 5.20
    if "a4" in path:
        return 0.00, 2.00
    return 0.00, 0.20


def _extract_grain(x: np.ndarray, center: int, P: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Return (n, segment, window) for a 2P grain centered at 'center'."""
    N = len(x)
    win = np.hanning(2 * P)
    a0 = center - P
    a1 = center + P

    # Clip and align window portion.
    w0 = 0
    if a0 < 0:
        w0 = -a0
        a0 = 0
    if a1 > N:
        a1 = N

    seg = x[a0:a1]
    w = win[w0:w0 + len(seg)]
    n = np.arange(a0 - center, a0 - center + len(seg))
    return n, seg, w


def _overlay_windows(ax, x: np.ndarray, marks: np.ndarray, P: int, center: int, s0: int, s1: int) -> None:
    """Overlay the sum of all 2P Hanning windows for marks that fall in [s0,s1]."""
    if len(marks) == 0:
        return

    wsum = np.zeros(len(x), dtype=np.float64)
    win = np.hanning(2 * P)
    for m in marks:
        if m < s0 - P or m > s1 + P:
            continue
        a0 = int(m) - P
        a1 = int(m) + P
        w0 = 0
        if a0 < 0:
            w0 = -a0
            a0 = 0
        if a1 > len(x):
            a1 = len(x)
        L = a1 - a0
        if L > 0:
            wsum[a0:a1] += win[w0:w0 + L]

    env = wsum[s0:s1]
    if len(env) == 0:
        return

    scale = float(np.max(np.abs(x[s0:s1]))) if np.max(np.abs(x[s0:s1])) > 0 else 1.0
    env = env / (np.max(env) if np.max(env) > 0 else 1.0)
    ax.plot(np.arange(s0 - center, s1 - center), env * scale, linewidth=1.0, alpha=0.8, label="window sum (scaled)")


def _fft_peak_hz(x: np.ndarray, fs_hz: int) -> float:
    x = np.asarray(x, dtype=np.float64)
    if len(x) == 0:
        return 0.0
    w = np.hanning(len(x))
    X = np.fft.rfft(x * w)
    mag = np.abs(X)
    k = int(np.argmax(mag[1:])) + 1 if len(mag) > 1 else 0
    return float(k * fs_hz / len(x))


def debug_plot_and_process(path: str) -> None:
    fs_hz = 48000

    # Hardcoded pitch shift.
    semitones = -2.0
    ratio = float(2.0 ** (semitones / 12.0))

    # --- Debug slice (few periods) ---
    start_s, end_s = _debug_time_window(path)
    x = pcm_waveform(path, fs_hz, start_s=start_s, end_s=end_s).astype(np.float64)

    y, dbg = td_psola_pitch_shift(
        x,
        fs_hz,
        ratio=ratio,
        fmin_hz=60.0,
        fmax_hz=800.0,
        f0_window_size=1024,
        f0_stride=256,
        f0_analysis_seconds=0.5,
        f0_max_frames=40,
    )

    P0 = dbg.get("period")
    if P0 is None:
        print("No f0/period detected in debug window; try changing start_s/end_s.")
        return

    P = int(P0)
    P_syn = int(dbg.get("period_syn") or P)

    marks_x = _pitch_marks_from_period(x, P)
    center_x = int(marks_x[len(marks_x) // 2]) if len(marks_x) else (len(x) // 2)

    marks_y = _pitch_marks_from_period(y, P_syn)
    center_y = int(marks_y[len(marks_y) // 2]) if len(marks_y) else (len(y) // 2)

    span_x = 5 * P
    s0x = max(0, center_x - span_x // 2)
    s1x = min(len(x), center_x + span_x // 2)
    nx = np.arange(s0x - center_x, s1x - center_x)

    span_y = 5 * P_syn
    s0y = max(0, center_y - span_y // 2)
    s1y = min(len(y), center_y + span_y // 2)
    ny = np.arange(s0y - center_y, s1y - center_y)

    n_x, seg_x, w_x = _extract_grain(x, center=center_x, P=P)
    w_x_scaled = w_x * (np.max(np.abs(seg_x)) if len(seg_x) else 1.0)

    n_y, seg_y, w_y = _extract_grain(y, center=center_y, P=P_syn)
    w_y_scaled = w_y * (np.max(np.abs(seg_y)) if len(seg_y) else 1.0)

    fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(10, 7), constrained_layout=True)

    ax1.plot(nx, x[s0x:s1x], linewidth=1.0)
    _overlay_windows(ax1, x, marks_x, P, center_x, s0x, s1x)
    ax1.set_title(f"Input waveform + windows (slice {start_s:g}s..{end_s:g}s), P={P} samples")
    ax1.set_xlabel("samples relative to input pitch mark")
    ax1.set_ylabel("x[n]")
    ax1.grid(True, alpha=0.3)
    ax1.legend(loc="upper right")

    ax2.plot(n_x, seg_x, label="input grain x", linewidth=1.0)
    ax2.plot(n_x, w_x_scaled, label="input Hanning (scaled)", linewidth=1.0)
    ax2.plot(n_x, seg_x * w_x, label="input windowed", linewidth=1.0)

    ax2.plot(n_y, seg_y, label="output grain y", linewidth=1.0, linestyle="--")
    ax2.plot(n_y, w_y_scaled, label="output Hanning (scaled)", linewidth=1.0, linestyle="--")
    ax2.plot(n_y, seg_y * w_y, label="output windowed", linewidth=1.0, linestyle="--")

    ax2.set_title(f"TD-PSOLA grains + Hanning windows (P={P}, P_syn={P_syn})")
    ax2.set_xlabel("samples relative to pitch mark")
    ax2.set_ylabel("amplitude")
    ax2.grid(True, alpha=0.3)
    ax2.legend(loc="upper right")

    ax3.plot(ny, y[s0y:s1y], linewidth=1.0)
    ax3.set_title(f"Output (debug slice), semitones={semitones:g}, ratio={ratio:.4f}")
    ax3.set_xlabel("samples relative to output pitch mark")
    ax3.set_ylabel("y[n]")
    ax3.grid(True, alpha=0.3)

    print("debug=", dbg)

    if "agg" in matplotlib.get_backend().lower():
        out_png = f"psola_debug_P{P}_Psyn{P_syn}.png"
        fig.savefig(out_png, dpi=150)
        plt.close(fig)
        print("wrote", out_png)
    else:
        plt.show()

    # --- Re-enable audio processing + write output ---
    # Use contour mode on the short debug slice (fast enough, and sounds much better
    # than forcing a single global period over a melody).
    x_proc = x
    y_proc, dbg_proc = td_psola_pitch_shift_contour(
        x_proc,
        fs_hz,
        ratio=ratio,
        fmin_hz=60.0,
        fmax_hz=800.0,
        f0_window_size=1024,
        f0_hop=256,
    )

    out_path = os.path.splitext(os.path.basename(path))[0] + f"_psola_debug_{semitones:+g}st.pcm"
    write_pcm_f32(out_path, y_proc)
    print("wrote", out_path)
    print("proc_debug=", dbg_proc)

    # --- Sanity checks ---
    # 1) autocorr-estimated f0 ratio on this short segment
    ex = estimate_f0_autocorr(x_proc, fs_hz, analysis_seconds=min(0.5, (end_s - start_s)), max_frames=40)
    ey = estimate_f0_autocorr(y_proc, fs_hz, analysis_seconds=min(0.5, (end_s - start_s)), max_frames=40)
    if ex and ey:
        print(f"autocorr_f0_hz: in={ex.f0_hz:.2f} out={ey.f0_hz:.2f} out/in={(ey.f0_hz/ex.f0_hz):.3f} expected={ratio:.3f}")

    # 2) quick spectrum plot (FFT peak can lock onto harmonics; use for shape/artifacts)
    n0 = len(x_proc) // 2
    win = 4096
    x_seg = x_proc[max(0, n0 - win // 2) : min(len(x_proc), n0 + win // 2)]
    y_seg = y_proc[max(0, n0 - win // 2) : min(len(y_proc), n0 + win // 2)]

    X = np.fft.rfft(x_seg * np.hanning(len(x_seg)))
    Y = np.fft.rfft(y_seg * np.hanning(len(y_seg)))
    f = np.fft.rfftfreq(len(x_seg), d=1.0 / fs_hz)

    fig2, ax = plt.subplots(1, 1, figsize=(10, 3), constrained_layout=True)
    ax.plot(f, 20 * np.log10(np.maximum(1e-12, np.abs(X))), label="input")
    ax.plot(f, 20 * np.log10(np.maximum(1e-12, np.abs(Y))), label="output")
    ax.set_xlim(0, 2000)
    ax.set_title("Magnitude spectrum (debug slice)")
    ax.set_xlabel("Hz")
    ax.set_ylabel("dB")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="upper right")

    if "agg" in matplotlib.get_backend().lower():
        out_png2 = "psola_debug_spectrum.png"
        fig2.savefig(out_png2, dpi=150)
        plt.close(fig2)
        print("wrote", out_png2)
    else:
        plt.show()

    # Full-file tuning pass sketch (DISABLED; uncomment when autocorr is accelerated):
    # x_full = read_pcm_f32(path)
    # y_full, dbg_full = td_psola_pitch_shift_contour(x_full, fs_hz, ratio=ratio)
    # write_pcm_f32("out_full.pcm", y_full)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: python psola.py <input.pcm>")
    debug_plot_and_process(sys.argv[1])


if __name__ == "__main__":
    main()
