"""PSOLA (Pitch-Synchronous Overlap-Add) with autocorr pitch marks.

Minimal flow:
1) load PCM (float32)
2) preprocess (LPF + center-clip denoise)
3) pitch marks from sliding autocorrelation (window=1024, hop=256)
4) PSOLA using *two-period* Hann windows
"""

import matplotlib.pyplot as plt
import numpy as np

import autocorrelation as ac


def pcm_waveform(filename: str, fs_hz: int, start_s: float, end_s: float) -> np.ndarray:
    with open(filename, "rb") as f:
        buffer = f.read()
        x = np.frombuffer(buffer, dtype=np.float32)

    start = int(fs_hz * start_s)
    end = int(fs_hz * end_s)
    return x[start:end]


def create_pitch_marks(
    signal: np.ndarray,
    fs_hz: float,
    window_size: int = 1024,
    hop_size: int = 256,
    fmin_hz: float = 50.0,
    fmax_hz: float = 2000.0,
) -> list[int]:
    """Sliding autocorrelation pitch marks (simple period-tracking)."""
    x = np.asarray(signal, dtype=np.float64)
    if x.size == 0:
        return []

    marks: list[int] = []
    period_n = None
    next_mark = 0

    for frame_start in range(0, x.size - window_size + 1, hop_size):
        frame = x[frame_start:frame_start + window_size]
        # Frame already preprocessed outside; just estimate period.
        _f0_hz, est_period = ac.estimate_f0_autocorr(
            frame,
            fs_hz=fs_hz,
            fmin_hz=fmin_hz,
            fmax_hz=fmax_hz,
            lpf_fc_hz=0.0,
            clip_ratio=0.30,
            threshold_ratio=0.2,
            use_hann=True,
        )
        if est_period is not None:
            if period_n is None:
                period_n = int(est_period)
            else:
                # Light smoothing to reduce jitter.
                period_n = int(round(0.8 * period_n + 0.2 * est_period))

        if period_n is None or period_n <= 0:
            continue

        frame_end = frame_start + window_size
        if next_mark < frame_start:
            # Jump next_mark forward near the current frame.
            k = (frame_start - next_mark + period_n - 1) // period_n
            next_mark += int(k) * period_n

        while next_mark < frame_end:
            if 0 <= next_mark < x.size:
                marks.append(int(next_mark))
            next_mark += period_n

    return sorted(set(marks))


def psola(signal: np.ndarray, pitch_marks: list[int], pitch_factor: float) -> np.ndarray:
    """PSOLA synthesis with 2-period Hann windows.

    pitch_factor:
        > 1 raises pitch (shorter synthesis periods)
        < 1 lowers pitch  (longer synthesis periods)

    Output length is the same as input length (time preserved).
    """
    x = np.asarray(signal, dtype=np.float64)
    n = int(x.size)
    if n == 0:
        return x.copy()
    if pitch_factor <= 0:
        raise ValueError("pitch_factor must be > 0")

    marks = sorted(int(m) for m in pitch_marks if 0 <= int(m) < n)
    if len(marks) < 3:
        return x.copy()

    y = np.zeros(n, dtype=np.float64)

    # Synthesis: place pitch-synchronous segments at synthesis positions.
    # Key idea: advance analysis index by 1/pitch_factor each synthesis step.
    # - pitch_factor > 1 => increment < 1 => duplicates segments (keeps duration)
    # - pitch_factor < 1 => increment > 1 => skips segments
    ai = 1.0

    # Start synthesis so the first segment can land near sample 0.
    s = int(max(marks[1] - marks[0], 0))
    while s < n:
        i = int(ai)
        if i < 1:
            i = 1
        if i > len(marks) - 2:
            i = len(marks) - 2  # repeat last usable segment to finish coverage

        m = marks[i]
        prev_m = marks[i - 1]
        next_m = marks[i + 1]

        # Synthesis period from local analysis period.
        local_p = int(round(0.5 * ((m - prev_m) + (next_m - m))))
        local_p = max(local_p, 1)
        synth_p = int(round(local_p / pitch_factor))
        synth_p = max(synth_p, 1)

        # Window spans two periods based on pitch marks.
        left_p = max(m - prev_m, 1)
        right_p = max(next_m - m, 1)
        start = max(0, m - left_p)
        end = min(n, m + right_p)

        if end > start + 2:
            seg = x[start:end].copy()
            seg *= np.hanning(seg.size)

            # Overlap-add around synthesis mark.
            anchor = m - start
            out_start = s - anchor
            out_end = out_start + seg.size

            seg_in_start = 0
            seg_in_end = seg.size

            if out_start < 0:
                seg_in_start = -out_start
                out_start = 0
            if out_end > n:
                seg_in_end -= out_end - n
                out_end = n

            if seg_in_end > seg_in_start:
                y[out_start:out_end] += seg[seg_in_start:seg_in_end]

        # Always advance to avoid stalling.
        s += synth_p
        ai += 1.0 / pitch_factor

    return y


def single_window_test() -> None:
    """Test PSOLA on one 1024-sample window (no sliding analysis)."""
    fs_hz = 48000
    n = 1024
    f0_true = 200.0
    pitch_factor = 1.8
    # pitch_factor = .9

    t = np.arange(n, dtype=np.float64) / fs_hz
    x = np.sin(2.0 * np.pi * f0_true * t)

    # Preprocess similar to the main pipeline.
    # x = x - float(np.mean(x))
    # x = ac.low_pass_filter_2(x, ac.alpha_calculation(fc_hz=500.0, fs_hz=fs_hz))
    # x = ac.remove_noise(x, clip_ratio=0.30)

    f0_in, period_n = ac.estimate_f0_autocorr(
        x,
        fs_hz=fs_hz,
        fmin_hz=80.0,
        fmax_hz=400.0,
        lpf_fc_hz=0.0,
        clip_ratio=0.30,
        threshold_ratio=0.2,
        use_hann=True,
    )
    if period_n is None:
        raise RuntimeError("single-window test: could not estimate pitch period")

    marks = list(range(0, n, int(period_n)))
    if len(marks) < 3:
        raise RuntimeError("single-window test: not enough pitch marks")

    y = psola(x, marks, pitch_factor)
    f0_out, _ = ac.estimate_f0_autocorr(
        y,
        fs_hz=fs_hz,
        fmin_hz=80.0,
        fmax_hz=400.0,
        lpf_fc_hz=0.0,
        clip_ratio=0.30,
        threshold_ratio=0.2,
        use_hann=True,
    )

    print(
        "single-window test:",
        "true_f0=", f0_true,
        "est_in=", f0_in,
        "est_out=", f0_out,
        "period_n=", period_n,
        "marks=", len(marks),
    )

    k = np.arange(n)
    plt.figure(figsize=(10, 4), constrained_layout=True)
    plt.plot(k, x, label="in", linewidth=0.9)
    plt.plot(k, y, label="out", linewidth=0.9, alpha=0.8)
    plt.title("Single-window PSOLA (N=1024)")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.show()
    # _show_or_save("py/single_window_psola.png")

if __name__ == "__main__":
    single_window_test()


    fs_hz = 48000
    window_size = 1024
    hop_size = 256
    pitch_factor = .7

    # Update these for your test case.
    filename = "py/twinkle.pcm"
    start_s = 2.5
    end_s = 7.0

    x = pcm_waveform(filename, fs_hz, start_s, end_s).astype(np.float64, copy=False)
    if x.size == 0:
        raise SystemExit("empty input")

    # Preprocess (same spirit as your autocorrelation pipeline).
    x = x - float(np.mean(x))
    x = ac.low_pass_filter_2(x, ac.alpha_calculation(fc_hz=1000.0, fs_hz=fs_hz))
    # x = ac.remove_noise(x, clip_ratio=0.30)

    marks = create_pitch_marks(
        x,
        fs_hz=float(fs_hz),
        window_size=window_size,
        hop_size=hop_size,
        fmin_hz=50.0,
        fmax_hz=1000.0,
    )
    print("pitch marks:", len(marks))

    y = psola(x, marks, pitch_factor)

    def track_f0(sig: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        f0s: list[float] = []
        prev = 0.0
        for start in range(0, sig.size - window_size + 1, hop_size):
            frame = sig[start:start + window_size]
            f0_hz, _period_n = ac.estimate_f0_autocorr(
                frame,
                fs_hz=fs_hz,
                fmin_hz=50.0,
                fmax_hz=2000.0,
                lpf_fc_hz=0.0,
                clip_ratio=0.30,
                threshold_ratio=0.2,
                use_hann=True,
            )
            if f0_hz is None:
                f0_hz = prev
            prev = float(f0_hz)
            f0s.append(prev)
        times = (np.arange(len(f0s)) * hop_size) / fs_hz
        return times, np.asarray(f0s, dtype=np.float64)

    # Frequency track before vs after PSOLA.
    t_in, f0_in = track_f0(x)

    y_dbg = y - float(np.mean(y))
    # y_dbg = ac.low_pass_filter_2(y_dbg, ac.alpha_calculation(fc_hz=500.0, fs_hz=fs_hz))
    # y_dbg = ac.remove_noise(y_dbg, clip_ratio=0.30)
    t_out, f0_out = track_f0(y_dbg)

    plt.figure(figsize=(10, 4), constrained_layout=True)
    plt.plot(t_in, f0_in, label="f0 in", linewidth=0.9)
    plt.plot(t_out, f0_out, label="f0 out", linewidth=0.9, alpha=0.8)
    plt.xlabel("time (s)")
    plt.ylabel("frequency (Hz)")
    plt.title("Estimated f0 before vs after PSOLA")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.show()
    # _show_or_save("py/f0_before_after_psola.png")

    n = np.arange(min(x.size, 5000))
    plt.figure(figsize=(10, 4), constrained_layout=True)
    plt.plot(n, x[: n.size], label="in", linewidth=0.8)
    plt.plot(n, y[: n.size], label="out", linewidth=0.8, alpha=0.8)
    plt.legend()
    plt.title("PSOLA input vs output (preview)")
    plt.grid(True, alpha=0.3)
    plt.show()