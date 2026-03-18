"""PSOLA (Pitch-Synchronous Overlap-Add) with autocorr pitch marks.

Minimal flow:
1) load PCM (float32)
2) preprocess (LPF + center-clip denoise)
3) pitch marks from sliding autocorrelation (window=1024, hop=256)
4) PSOLA using *two-period* Hann windows
"""

import matplotlib.pyplot as plt
import numpy as np
import subprocess

import autocorrelation as ac


def pcm_waveform(filename: str, fs_hz: int, start_s: float, end_s: float) -> np.ndarray:
    with open(filename, "rb") as f:
        buffer = f.read()
        x = np.frombuffer(buffer, dtype=np.float32)

    start = int(fs_hz * start_s)
    end = int(fs_hz * end_s)
    return x[start:end]


def mp3_to_pcm_waveform(
    input_mp3: str,
    fs_hz: int,
    out_pcm: str,
) -> None:
    """Convert MP3 to float32 PCM with ffmpeg."""

    #TODO: make pcm input mono channel
    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-i",
        input_mp3,
        "-f",
        "f32le",
        "-acodec",
        "pcm_f32le",
        "-ar",
        str(fs_hz),
        out_pcm,
    ]
    try:
        subprocess.run(ffmpeg_cmd, check=True, stdout=subprocess.DEVNULL)
    except FileNotFoundError as exc:
        raise RuntimeError("ffmpeg not found on PATH") from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"ffmpeg failed with exit code {exc.returncode}") from exc


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


def psola(
    signal: np.ndarray,
    pitch_marks: list[int],
    pitch_factor: float,
    phase_offset: int = -1,
    hop: int = 0,
) -> tuple[np.ndarray, int]:
    """PSOLA synthesis with 2-period Hann windows.

    pitch_factor:
        > 1 raises pitch (shorter synthesis periods)
        < 1 lowers pitch  (longer synthesis periods)

    phase_offset: synthesis starting position to maintain grid continuity with
        the previous chunk (-1 = use default = marks[1]-marks[0]).
        Hardware analog: a register holding the carry-over synthesis position.

    hop: chunk hop size in samples. When > 0, next_phase_offset is computed as
        (s_exit - hop) % last_synth_p so the caller can pass it to the next chunk.

    Returns (y, next_phase_offset). next_phase_offset is -1 if hop == 0.

    Output length is the same as input length (time preserved).
    """
    x = np.asarray(signal, dtype=np.float64)
    n = int(x.size)
    if n == 0:
        return x.copy(), -1
    if pitch_factor <= 0:
        raise ValueError("pitch_factor must be > 0")

    marks = sorted(int(m) for m in pitch_marks if 0 <= int(m) < n)
    if len(marks) < 3:
        return x.copy(), -1

    y = np.zeros(n, dtype=np.float64)
    w = np.zeros(n, dtype=np.float64)

    # Synthesis: place pitch-synchronous segments at synthesis positions.
    # Key idea: advance analysis index by 1/pitch_factor each synthesis step.
    # - pitch_factor > 1 => increment < 1 => duplicates segments (keeps duration)
    # - pitch_factor < 1 => increment > 1 => skips segments
    ai = 1.0

    # Use phase_offset to continue the synthesis grid from the previous chunk.
    # Without it, resetting s here breaks phase continuity at every chunk boundary.
    default_s = int(max(marks[1] - marks[0], 0))
    s = phase_offset if phase_offset >= 0 else default_s
    last_synth_p = default_s if default_s > 0 else 1
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
        last_synth_p = synth_p

        # Window spans two periods based on pitch marks.
        left_p = max(m - prev_m, 1)
        right_p = max(next_m - m, 1)
        start = max(0, m - left_p)
        end = min(n, m + right_p)

        if end > start + 2:
            win = np.hanning(end - start)
            seg = x[start:end].copy()
            seg *= win

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
                w[out_start:out_end] += win[seg_in_start:seg_in_end]

        # Always advance to avoid stalling.
        s += synth_p
        ai += 1.0 / pitch_factor

    # Compute next_phase_offset so the caller can maintain synthesis grid continuity.
    # s is now the first position >= n (the "exit" value). In the next chunk (offset
    # by hop samples), the synthesis should start at (s - hop) % last_synth_p.
    # This ensures grains land at the same global phase positions across chunk boundaries.
    # Hardware analog: subtract hop from the carry register, take modulo synth_period.
    next_phase_offset = (s - hop) % last_synth_p if hop > 0 and last_synth_p > 0 else -1

    # Normalize by accumulated window weights to remove amplitude artifacts.
    safe_w = np.where(w > 1e-8, w, 1.0)
    y /= safe_w
    return y, next_phase_offset


def export_psola_output(
    y: np.ndarray,
    fs_hz: int,
    out_pcm: str,
    out_mp3: str,
) -> None:
    """Save PSOLA output as float32 PCM, then convert to MP3 with ffmpeg."""
    y_f32 = y.astype(np.float32, copy=False)
    y_f32.tofile(out_pcm)

    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "f32le",
        "-ar",
        str(fs_hz),
        "-ac",
        "1",
        "-i",
        out_pcm,
        out_mp3,
    ]
    try:
        subprocess.run(ffmpeg_cmd, check=True, stdout=subprocess.DEVNULL)
        print("wrote:", out_pcm)
        print("wrote:", out_mp3)
    except FileNotFoundError as exc:
        raise RuntimeError("ffmpeg not found on PATH") from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"ffmpeg failed with exit code {exc.returncode}") from exc


def _find_first_zero_crossing(signal: np.ndarray, start: int, period_n: int) -> int:
    """Find the first positive-going zero crossing within one period of start.

    Hardware analog: single comparator (prev <= 0 AND curr > 0), 1 counter, 1 latch.
    """
    search_end = min(start + period_n, len(signal) - 1)
    for i in range(start, search_end):
        if signal[i] <= 0.0 < signal[i + 1]:
            return i + 1
    return start  # fallback: no crossing found


def create_pitch_marks_chunk(
    signal: np.ndarray,
    fs_hz: float,
    fmin_hz: float = 50.0,
    fmax_hz: float = 1000.0,
    prev_period: int | None = None,
) -> tuple[list[int], int | None]:
    """Single-frame pitch mark placement for a fixed-size chunk.

    Simplified variant of create_pitch_marks for use when the signal is
    exactly one analysis window (1024 samples).  A single autocorrelation
    estimate gives the period; IIR smoothing with prev_period reduces
    inter-chunk jitter; marks are anchored to the first zero crossing.

    Returns (marks, smoothed_period).
    Hardware analog: period stored in a single 27-bit register updated each chunk.
    """
    x = np.asarray(signal, dtype=np.float64)
    _f0, period_n = ac.estimate_f0_autocorr(
        x,
        fs_hz=fs_hz,
        fmin_hz=fmin_hz,
        fmax_hz=fmax_hz,
        lpf_fc_hz=0.0,
        clip_ratio=0.30,
        threshold_ratio=0.2,
        use_hann=True,
    )

    # IIR smoothing across chunks to prevent period discontinuities at boundaries.
    # Hardware: period_reg <= 0.8*period_reg + 0.2*new_period (one MAC, like lpf.sv).
    if period_n is not None and prev_period is not None:
        period_n = int(round(0.8 * prev_period + 0.2 * period_n))
    elif period_n is None:
        period_n = prev_period  # hold last known good value

    if not period_n:
        return [], None

    period_n = int(round(period_n))
    anchor = _find_first_zero_crossing(x, 0, period_n)
    return list(range(anchor, x.size, period_n)), period_n


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

    y, _ = psola(x, marks, pitch_factor)
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
    # single_window_test()


    fs_hz = 48000
    window_size = 1024
    hop_size = 256
    note_step = 2
    pitch_factor = 2**(note_step/12)
    print("pitch_factor", pitch_factor)

    # Update these for your test case.
    import os
    filename = os.path.join(os.path.dirname(__file__), "twinkle.pcm")
    start_s = 2.5
    end_s = 7.0

    # mp3_to_pcm_waveform(input_mp3, fs_hz, generated_pcm)
    x = pcm_waveform(filename, fs_hz, start_s, end_s).astype(np.float64, copy=False)
    if x.size == 0:
        raise SystemExit("empty input")

    # Preprocess (same spirit as your autocorrelation pipeline).
    # x = x - float(np.mean(x))
    # x = ac.low_pass_filter_2(x, ac.alpha_calculation(fc_hz=1300.0, fs_hz=fs_hz))
    # x = ac.remove_noise(x, clip_ratio=0.30)

    # --- Chunked real-time simulation ---
    # Process independent 1024-sample chunks with 512-sample hop.
    # Adjacent chunks are crossfaded over their 512-sample overlap to avoid
    # discontinuities at boundaries.
    chunk_size = 1024
    hop = chunk_size // 2  # 512

    # Energy threshold for voiced/unvoiced detection.
    # Hardware: compare sum_of_squares > ENERGY_THRESHOLD^2 * N (avoids sqrt).
    ENERGY_THRESHOLD = 1e-4

    alpha = ac.alpha_calculation(fc_hz=1000.0, fs_hz=fs_hz)
    fade_in  = np.linspace(0.0, 1.0, hop)
    fade_out = np.linspace(1.0, 0.0, hop)

    y_chunks: list[np.ndarray] = []
    prev_out: np.ndarray | None = None
    prev_period: int | None = None   # IIR period state threaded across chunks
    phase_offset: int = -1           # synthesis grid carry-over across chunks

    for i in range(0, x.size - chunk_size + 1, hop):
        chunk = x[i : i + chunk_size].copy()
        chunk -= float(np.mean(chunk))
        chunk_low = ac.low_pass_filter_2(chunk, alpha)

        # Voiced/unvoiced detection: skip PSOLA on silent/noisy chunks.
        # Hardware: accumulate squared samples, compare to threshold^2 * N.
        rms = float(np.sqrt(np.mean(chunk_low ** 2)))
        if rms < ENERGY_THRESHOLD:
            chunk_out = chunk.copy()
            # Reset phase on silence: the passthrough signal has its own phase,
            # so the synthesis grid from the last voiced chunk is no longer valid.
            phase_offset = -1
        else:
            marks, prev_period = create_pitch_marks_chunk(
                chunk_low, fs_hz=float(fs_hz), fmin_hz=50.0, fmax_hz=1000.0,
                prev_period=prev_period,
            )
            chunk_out, phase_offset = psola(chunk, marks, pitch_factor,
                                            phase_offset=phase_offset, hop=hop)

        if prev_out is None:
            # First chunk: emit first half directly (no previous chunk to blend with)
            y_chunks.append(chunk_out[:hop].copy())
        else:
            # Crossfade: prev chunk's tail fades out, current chunk's head fades in.
            # fade_out + fade_in == 1.0 at every sample, so amplitude is bounded.
            blended = fade_out * prev_out[hop:] + fade_in * chunk_out[:hop]
            y_chunks.append(blended)

        prev_out = chunk_out

    # Flush the second half of the last processed chunk.
    if prev_out is not None:
        y_chunks.append(prev_out[hop:].copy())

    y = np.concatenate(y_chunks)
    print("chunks processed:", (x.size - chunk_size) // hop + 1, "| output samples:", y.size)

    out_pcm = os.path.join(os.path.dirname(__file__), "twinkle_out.pcm")
    out_mp3 = os.path.join(os.path.dirname(__file__), "twinkle_out.mp3")
    export_psola_output(y=y, fs_hz=fs_hz, out_pcm=out_pcm, out_mp3=out_mp3)

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

    # y_dbg = y - float(np.mean(y))
    # y_dbg = ac.low_pass_filter_2(y_dbg, ac.alpha_calculation(fc_hz=500.0, fs_hz=fs_hz))
    # y_dbg = ac.remove_noise(y_dbg, clip_ratio=0.30)
    # t_out, f0_out = track_f0(y_dbg)
    t_out, f0_out = track_f0(y)

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
