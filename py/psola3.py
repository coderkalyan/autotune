"""Streaming-friendly TD-PSOLA with time-varying target frequency.

Think of this file as a tiny music robot:
1. It listens to short chunks of sound and guesses the period (how many samples
    until the waveform pattern repeats).
2. It marks beat-like points called epochs.
3. Around each epoch, it cuts out a small sound chunk (a grain), smooths the
    chunk edges with a Hann window, then overlaps many grains to build output.

Because we can control how far apart output grains are placed, we can change
the perceived pitch over time.

RTL translation guide (big picture):
- Stage A: input sample stream + frame buffer + autocorrelation period detector.
- Stage B: epoch generator (free-running counter stepped by period estimate).
- Stage C: grain extractor (2T samples around each epoch) + Hann multiplier.
- Stage D: overlap-add engine that writes grains into an output accumulation RAM.
- Stage E: normalization/clamp + output formatting.

If you implement this in Verilog, think in terms of separate modules connected by
FIFO handshakes, not one giant always block.
"""

from __future__ import annotations

from dataclasses import dataclass
import os
import wave
from tqdm import tqdm

import numpy as np

import autocorrelation as ac


@dataclass
class Grain:
    """One prepared sound chunk used during synthesis.

    center: sample index where this grain is centered in time.
    period: local pitch period (in samples) near that center.
    samples: the actual grain waveform (already windowed/smoothed).

    RTL note:
    - `center` maps to an absolute sample counter value (timestamp).
    - `period` maps to a control word produced by the pitch tracker.
    - `samples` maps to a RAM region or streaming FIFO payload.
    """

    center: int
    period: int
    samples: np.ndarray


def read_pcm_f32(path: str, fs_hz: int, start_s: float = 0.0, end_s: float | None = None) -> np.ndarray:
    """Read raw float32 PCM and return a selected time slice as float64.

        Raw PCM has no header, so we just interpret bytes as float32 samples.

        RTL equivalent:
        - This would be replaced by an ADC/I2S receiver or DMA reader feeding
            samples into a circular buffer.
    """

    with open(path, "rb") as f:
        buffer = f.read()
    x = np.frombuffer(buffer, dtype=np.float32)
    if x.size == 0:
        return x.astype(np.float64, copy=False)

    start = int(fs_hz * start_s)
    if end_s is None:
        end = x.size
    else:
        end = int(fs_hz * end_s)
    # Clamp slice indexes so we never go out of bounds.
    start = max(0, min(start, x.size))
    end = max(start, min(end, x.size))
    return x[start:end].astype(np.float64, copy=False)


def write_pcm_f32(path: str, y: np.ndarray) -> None:
    """Write samples as raw float32 PCM bytes.

    RTL equivalent:
    - This is like writing final stream samples to DAC/I2S or memory.
    """

    y_f32 = np.asarray(y, dtype=np.float32)
    y_f32.tofile(path)


def write_wav_int16(path: str, y: np.ndarray, fs_hz: int) -> None:
    """Write mono WAV so the result is easy to listen to in common players.

    RTL equivalent:
    - The WAV container part is software-only convenience.
    - The useful hardware idea is the final clamp/quantize to fixed width.
    """

    if y.size == 0:
        return
    y_f64 = np.asarray(y, dtype=np.float64)
    # WAV int16 range is [-32768, 32767], so first clamp to [-1, 1].
    y_clip = np.clip(y_f64, -1.0, 1.0)
    y_i16 = (y_clip * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(fs_hz))
        wf.writeframes(y_i16.tobytes())


def create_epochs(
    signal: np.ndarray,
    *,
    fs_hz: float,
    window_size: int = 1024,
    hop_size: int = 256,
    fmin_hz: float = 80.0,
    fmax_hz: float = 1000.0,
    lpf_fc_hz: float = 0.0,
    clip_ratio: float = 0.30,
    threshold_ratio: float = 0.2,
    smoothing: float = 0.2,
) -> list[tuple[int, int]]:
    """Estimate pitch period frame-by-frame and generate epoch positions.

    Returns a list of (epoch_center_sample, period_samples).

    Conceptually, this is a control-plane stage:
    1. Run period estimator on overlapping frames.
    2. Smooth period so timing does not jitter too much.
    3. Run a free-running epoch clock using that period.

    RTL mapping idea:
    - Input RAM window reader: emits 1024-sample frame every 256 samples.
    - Autocorrelation core: outputs `est_period_valid` + `est_period`.
    - Period smoother: one multiply-accumulate update per frame.
    - Epoch scheduler: counter compares against frame boundaries.
    """

    # In Python we use float64 for convenience and numerical headroom.
    # In RTL you will likely use fixed-point, e.g. Q1.15 or Q2.22.
    x = np.asarray(signal, dtype=np.float64)
    if x.size == 0:
        return []

    epochs: list[tuple[int, int]] = []
    # `period_n` is the currently accepted period estimate in samples.
    period_n: int | None = None
    # `next_epoch` is an absolute sample index where the next epoch should land.
    next_epoch = 0

    # Slide by hop_size, so frames overlap. This matches common streaming DSP.
    for frame_start in tqdm(range(0, x.size - window_size + 1, hop_size)):
        frame = x[frame_start:frame_start + window_size]
        # Period estimator is hidden in `autocorrelation.py`.
        # Hardware version would often be pipelined and multi-cycle.
        _f0_hz, est_period = ac.estimate_f0_autocorr(
            frame,
            fs_hz=fs_hz,
            fmin_hz=fmin_hz,
            fmax_hz=fmax_hz,
            lpf_fc_hz=lpf_fc_hz,
            clip_ratio=clip_ratio,
            threshold_ratio=threshold_ratio,
            use_hann=True,
        )

        # Smooth period changes so epochs do not jump too much frame-to-frame.
        # Equation: new = (1-a)*old + a*estimate, where a=`smoothing`.
        # In fixed-point hardware this is a weighted sum with right shifts.
        if est_period is not None:
            if period_n is None:
                period_n = int(est_period)
            else:
                period_n = int(round((1.0 - smoothing) * period_n + smoothing * est_period))

        # Until we have a valid period, we cannot schedule epochs.
        if period_n is None or period_n <= 0:
            continue

        frame_end = frame_start + window_size
        # If our free-running epoch clock is behind, fast-forward it.
        # This avoids generating stale epochs from old frames.
        if next_epoch < frame_start:
            k = (frame_start - next_epoch + period_n - 1) // period_n
            next_epoch += int(k) * period_n

        # Emit every epoch that lands inside this frame.
        # In hardware this becomes repeated writes to an epoch FIFO.
        while next_epoch < frame_end:
            if 0 <= next_epoch < x.size:
                epochs.append((int(next_epoch), int(period_n)))
            next_epoch += period_n

    return epochs


def extract_grain_samples(signal: np.ndarray, center: int, period: int) -> np.ndarray:
    """Cut a 2*period sample grain centered at `center`.

    If the grain would extend outside the signal, zero-pad the missing part.

    RTL mapping idea:
    - `signal` would be a circular buffer RAM.
    - Address generator reads from [center-period, center+period).
    - Out-of-range reads inject zeros (boundary guard logic).
    """

    # TD-PSOLA grain length is 2T in this prototype.
    # Many systems use 2T or 3T depending on quality/latency goals.
    length = 2 * int(period)
    if length <= 0:
        return np.zeros(0, dtype=np.float64)

    # Pre-fill with zeros, then overwrite with any valid overlap from input.
    grain = np.zeros(length, dtype=np.float64)
    start = center - period
    end = center + period

    # Compute source overlap in input signal coordinates.
    # [start, end) is desired read range. Clip it to valid signal range.
    src_start = max(0, start)
    src_end = min(len(signal), end)
    if src_end > src_start:
        # Map source overlap into destination grain coordinates.
        # Example: if start=-4, first 4 destination samples stay zero.
        dst_start = src_start - start
        dst_end = dst_start + (src_end - src_start)
        grain[dst_start:dst_end] = signal[src_start:src_end]

    return grain


def build_grain_queue(
    signal: np.ndarray,
    epochs: list[tuple[int, int]],
) -> tuple[list[np.ndarray], list[Grain]]:
    """Build grains for all epochs and apply a Hann window to each grain.

    Returns:
    - sample_buffer: raw (unwindowed) grains
    - grains: Grain objects containing windowed samples

    Why windowing matters:
    - Hard-cut chunks have sharp edges, which sound like clicks.
    - Hann fades edges toward zero, making overlap smoother.

    RTL mapping idea:
    - Hann LUT ROM addressed by sample index inside grain.
    - Multiplier computes raw_sample * hann_coeff.
    - Windowed grain written to grain RAM or streamed forward.
    """

    sample_buffer: list[np.ndarray] = []
    grains: list[Grain] = []

    # Each epoch creates one candidate grain.
    for center, period in tqdm(epochs):
        raw = extract_grain_samples(signal, center=center, period=period)
        if raw.size == 0:
            continue
        sample_buffer.append(raw)

        # Windowing fades grain edges to reduce clicks during overlap-add.
        window = np.hanning(raw.size)
        windowed = raw * window
        # Store both timing metadata and waveform payload.
        grains.append(Grain(center=center, period=period, samples=windowed))

    return sample_buffer, grains


def make_target_curve(points: list[tuple[float, float]]):
    """Create a function that returns target f0 (Hz) at time t (seconds).

    Points are (time_s, f0_hz). Between points, this does linear interpolation.

    RTL mapping idea:
    - Store control points in a tiny ROM.
    - A control FSM selects active segment (t0,f0)->(t1,f1).
    - A linear interpolator computes target_f0 each control tick.
    """

    if not points:
        raise ValueError("target curve points must be non-empty")
    # Sort once so interpolation scan is monotonic in time.
    points = sorted(points, key=lambda p: p[0])

    def target_f0_at_time(t_s: float) -> float:
        # Clamp before first / after last point.
        if t_s <= points[0][0]:
            return float(points[0][1])
        if t_s >= points[-1][0]:
            return float(points[-1][1])
        # Find the segment that contains t_s and interpolate inside it.
        # alpha in [0,1] blends from left point to right point.
        for (t0, f0), (t1, f1) in zip(points[:-1], points[1:]):
            if t0 <= t_s <= t1:
                if t1 == t0:
                    return float(f1)
                alpha = (t_s - t0) / (t1 - t0)
                return float((1.0 - alpha) * f0 + alpha * f1)
        return float(points[-1][1])

    return target_f0_at_time


def synthesize_pitch_shift(
    grains: list[Grain],
    n_samples: int,
    *,
    fs_hz: float,
    target_f0_at_time=None,
    use_target_curve: bool = True,
    constant_pitch_factor: float = 1.0,
) -> np.ndarray:
    """Overlap-add grains with either target-curve autotune or fixed transposition.

    `ai` walks through analysis grains.
    `s` walks through synthesis (output) time.

    Core PSOLA idea here:
    - Keep grain shapes mostly from original voice.
    - Change where/when grains are placed in output.
    - Placement density changes perceived pitch.

    RTL mapping idea:
    - Grain reader: fetches one grain payload by index.
    - Placement engine: computes output write address window.
    - Accumulator RAM: adds overlapping grains sample-by-sample.
    - Control path updates `s` and `ai` each grain event.
    """

    y = np.zeros(int(n_samples), dtype=np.float64)
    if not grains:
        return y

    # `ai` can be fractional. int(ai) chooses the current grain index.
    # In hardware this is often a fixed-point phase accumulator.
    ai = 0.0
    # `s` is output sample cursor where next grain center is placed.
    s = int(grains[0].center)
    last_idx = len(grains) - 1

    # One loop iteration ~= one grain placement event.
    while s < n_samples:
        # Pick analysis grain by truncating ai and clamping bounds.
        i = int(ai)
        if i < 0:
            i = 0
        if i > last_idx:
            i = last_idx

        grain = grains[i]
        # period T controls both grain span and synthesis hop size.
        period = int(grain.period)
        length = int(grain.samples.size)
        if length > 0:
            # Place the grain so its center lands at output sample s.
            start = s - period
            end = start + length
            # Clip write range to valid output bounds.
            out_start = max(0, start)
            out_end = min(n_samples, end)
            if out_end > out_start:
                # Map output overlap back into grain coordinates.
                g_start = out_start - start
                g_end = g_start + (out_end - out_start)
                # Overlap-add: multiple grains can contribute to same output sample.
                y[out_start:out_end] += grain.samples[g_start:g_end]

        if period <= 0:
            pitch_factor = 1.0
        elif not use_target_curve:
            # Constant-factor mode: scale everything uniformly.
            pitch_factor = float(constant_pitch_factor)
            if pitch_factor <= 0.0:
                pitch_factor = 1.0
        else:
            # Target mode: follow user-defined target f0(t).
            # f0 = sample_rate / period_samples.
            current_f0 = float(fs_hz) / float(period)
            target_f0 = 0.0 if target_f0_at_time is None else float(target_f0_at_time(s / float(fs_hz)))
            if current_f0 > 0.0 and target_f0 > 0.0:
                # >1 means pitch up, <1 means pitch down.
                pitch_factor = target_f0 / current_f0
            else:
                pitch_factor = 1.0
        
        # Synthesis hop in samples:
        #   hop_out ~= T / pitch_factor
        # If pitch_factor is 2.0 (one octave up), hop roughly halves.
        # Shorter hop -> denser grains -> higher pitch impression.
        synth_hop = max(1, int(round(period / pitch_factor)))
        s += synth_hop
        # Keep analysis pointer moving in the opposite proportion.
        # If output hops are short (pitch up), analysis advances slower.
        ai += 1.0 / pitch_factor

    return y


def run_pass_through(
    input_pcm: str,
    output_pcm: str,
    output_wav: str,
    *,
    fs_hz: int = 48000,
    start_s: float = 0.0,
    end_s: float | None = None,
    use_target_curve: bool = True,
    constant_pitch_factor: float = 2 ** (2 / 12),
    target_points_hz: list[tuple[float, float]] | None = None,
) -> np.ndarray:
    """Full pipeline: read input, detect epochs, synthesize, then write output.

    This is orchestrator code (top-level control), similar to what a testbench or
    software driver would do around RTL modules.
    """

    # Step 1: load a signal segment.
    x = read_pcm_f32(input_pcm, fs_hz=fs_hz, start_s=start_s, end_s=end_s)
    if x.size == 0:
        raise SystemExit("empty input")

    # Step 2: estimate period and generate epochs.
    epochs = create_epochs(
        x,
        fs_hz=float(fs_hz),
        window_size=1024,
        hop_size=256,
        fmin_hz=80.0,
        fmax_hz=1000.0,
        lpf_fc_hz=0.0,
        clip_ratio=0.30,
        threshold_ratio=0.2,
        smoothing=0.2,
    )
    if len(epochs) == 0:
        raise RuntimeError("no epochs found")
    print("found epochs")
    print(epochs[10000:10005])

    # Step 3: extract + window grains.
    sample_buffer, grains = build_grain_queue(x, epochs)
    print("epochs:", len(epochs), "grains:", len(sample_buffer))

    # Step 4: derive a base pitch to build a target pitch curve.
    duration_s = x.size / float(fs_hz)
    periods = [p for _c, p in epochs if p > 0]
    if not periods:
        raise RuntimeError("no valid periods for target curve")
    median_period = float(np.median(periods))
    base_f0 = float(fs_hz) / median_period

    # Mode selection:
    # - use_target_curve=True: autotune against target points below.
    # - use_target_curve=False: ignore target and use constant_pitch_factor.
    
    # Demo target: every 0.1 s, move up one semitone.
    # Formula: frequency ratio per semitone = 2^(1/12).
    # Note: this demo currently overwrites `target_points_hz` input on purpose
    # for quick experiments. For production, remove this overwrite.
    target_points_hz = []
    for i in range(10):
        target_points_hz.append((i / 10.0, base_f0 * (2 ** (i / 12))))

    # target_f0_at_time = None
    
    if use_target_curve:
        # If caller did not provide a curve, choose one preset below.
        # QUICK TOGGLE: uncomment ONE preset block and keep others commented.
        if target_points_hz is None:
            # Preset A (default): lock to base pitch (flat target).
            target_points_hz = [
                (0.0, base_f0),
                (duration_s, base_f0),
            ]

            # Preset B: lock to +2 semitones above base pitch.
            # up_2st = base_f0 * (2 ** (2 / 12))
            # target_points_hz = [
            #     (0.0, up_2st),
            #     (duration_s, up_2st),
            # ]

            # Preset C: expressive contour (up then down then return).
            # up_2st = base_f0 * (2 ** (2 / 12))
            # down_2st = base_f0 * (2 ** (-2 / 12))
            # target_points_hz = [
            #     (0.0, base_f0),
            #     (0.35 * duration_s, up_2st),
            #     (0.70 * duration_s, down_2st),
            #     (duration_s, base_f0),
            # ]

        # Step 5a: convert points into a callable target f0(t).
        target_f0_at_time = make_target_curve(target_points_hz)
        print("mode: target curve")
        print("target curve (Hz):", target_points_hz)
    else:
        # Step 5b: constant transposition mode (global scale change).
        print("mode: constant pitch factor")
        print("constant pitch factor:", constant_pitch_factor)

    # Step 6: run PSOLA overlap-add synthesis with time-varying target pitch.
    y = synthesize_pitch_shift(
        grains,
        n_samples=x.size,
        fs_hz=float(fs_hz),
        target_f0_at_time=target_f0_at_time,
        use_target_curve=use_target_curve,
        constant_pitch_factor=constant_pitch_factor,
    )

    # Step 7: write outputs in raw and WAV formats.
    write_pcm_f32(output_pcm, y)
    write_wav_int16(output_wav, y, fs_hz=fs_hz)
    print("wrote:", output_pcm)
    print("wrote:", output_wav)

    return y


if __name__ == "__main__":
    # Small command-line runnable example.
    # In an RTL project, this role is similar to a stimulus script or host app
    # that feeds samples and reads processed samples.
    fs_hz = 48000
    input_pcm = "twinkle.pcm"

    base, _ext = os.path.splitext(input_pcm)
    output_pcm = f"{base}_psola3_target.pcm"
    output_wav = f"{base}_psola3_target.wav"

    # Easy mode toggle:
    # True  -> target-based autotune (uses target presets in run_pass_through)
    # False -> constant transposition using constant_pitch_factor
    use_target_curve = False
    # Example: +2 semitones for constant mode.
    constant_pitch_factor = 2 ** (2 / 12)

    run_pass_through(
        input_pcm=input_pcm,
        output_pcm=output_pcm,
        output_wav=output_wav,
        fs_hz=fs_hz,
        start_s=0.0,
        end_s=None,
        use_target_curve=use_target_curve,
        constant_pitch_factor=constant_pitch_factor,
    )
