"""Streaming-friendly TD-PSOLA with time-varying target frequency.

This prototype mirrors the RTL-oriented architecture:
- sliding autocorrelation to estimate period T
- free-running epochs
- 2T Hann-windowed grains queued and overlap-added at epoch centers
"""

from __future__ import annotations

from dataclasses import dataclass
import os
from typing import Callable
import wave
from tqdm import tqdm

import numpy as np

import autocorrelation as ac


@dataclass
class Grain:
    """One prepared TD-PSOLA grain used by the synthesis stage.

    center: absolute sample index where this grain was extracted.
    period: local pitch period T (in samples) around `center`.
    samples: windowed grain waveform, length typically 2T.

    RTL mapping idea:
    - center -> timestamp/control metadata.
    - period -> pitch tracker output word.
    - samples -> payload stored in RAM/FIFO.
    """

    center: int
    period: int
    samples: np.ndarray


@dataclass
class TargetConfig:
    """Resolved target-pitch configuration for synthesis.

    target_f0_at_time: callable f(t_s) -> target f0 in Hz.
    selected_points: concrete control points used for curve mode.
    selected_const_hz: scalar target frequency used for constant-Hz mode.

    This wrapper lets run_pass_through print what target was chosen
    without needing to branch on many return shapes.
    """

    target_f0_at_time: Callable[[float], float]
    selected_points: list[tuple[float, float]] | None
    selected_const_hz: float | None


def read_pcm_f32(path: str, fs_hz: int, start_s: float = 0.0, end_s: float | None = None) -> np.ndarray:
    """Read raw float32 PCM and return selected slice as float64.

    Raw PCM has no header, so we directly interpret bytes as float32 samples.
    The time slicing arguments provide a simple testbench-style windowing control.

    RTL equivalent:
    - Replace file read with ADC/I2S/DMA sample stream.
    - Replace slicing with sample-counter based gate logic.
    """

    with open(path, "rb") as f:
        buffer = f.read()
    samples_f32 = np.frombuffer(buffer, dtype=np.float32)
    if samples_f32.size == 0:
        return samples_f32.astype(np.float64, copy=False)

    start = int(fs_hz * start_s)
    if end_s is None:
        end = samples_f32.size
    else:
        end = int(fs_hz * end_s)
    # Clamp slice bounds to avoid out-of-range indexing.
    start = max(0, min(start, samples_f32.size))
    end = max(start, min(end, samples_f32.size))
    return samples_f32[start:end].astype(np.float64, copy=False)


def write_pcm_f32(path: str, signal: np.ndarray) -> None:
    """Write samples to raw float32 PCM.

    RTL equivalent:
    - Stream output samples to DAC/I2S or memory sink.
    """

    signal_f32 = np.asarray(signal, dtype=np.float32)
    signal_f32.tofile(path)


def write_wav_int16(path: str, signal: np.ndarray, fs_hz: int) -> None:
    """Write mono int16 WAV for easy listening.

    WAV packaging is software convenience; the key DSP step mirrored in hardware
    is clamp + quantize to a fixed output width.
    """

    if signal.size == 0:
        return
    signal_f64 = np.asarray(signal, dtype=np.float64)
    # Clamp to normalized range before int16 conversion.
    signal_clipped = np.clip(signal_f64, -1.0, 1.0)
    signal_i16 = (signal_clipped * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(fs_hz))
        wf.writeframes(signal_i16.tobytes())


def extract_grain_samples(signal: np.ndarray, center: int, period: int) -> np.ndarray:
    """Extract one 2T grain centered at `center` with zero-padding at edges.

    TD-PSOLA uses local periodic chunks. Here we pick [center-T, center+T).

    RTL mapping idea:
    - Circular buffer read window around epoch.
    - Boundary guard injects zeros when read address is invalid.
    """

    length = 2 * int(period)
    if length <= 0:
        return np.zeros(0, dtype=np.float64)

    # Allocate destination grain and copy only valid input overlap.
    grain = np.zeros(length, dtype=np.float64)
    # Normal (ideal) grain read window in absolute input coordinates.
    # This is what we would read if the signal were infinite.
    start = center - period
    end = center + period

    # Source interval we want is [start, end). Clip to valid signal bounds.
    # src_start/src_end are in absolute input-signal coordinates.
    src_start = max(0, start)
    src_end = min(len(signal), end)
    if src_end > src_start:
        # Convert absolute source coordinates into grain-local coordinates.
        # If start < 0, the grain begins with zero-padding, so dst_start shifts right.
        # In general: grain index j corresponds to absolute sample (start + j).
        dst_start = src_start - start
        dst_end = dst_start + (src_end - src_start)
        grain[dst_start:dst_end] = signal[src_start:src_end]

    return grain


def make_target_curve(points: list[tuple[float, float]]):
    """Build target f0(t) interpolator from control points.

    Input points are (time_seconds, frequency_hz). Evaluation is piecewise-linear,
    with clamping before the first point and after the last point.

    RTL mapping idea:
    - Small control-point ROM
    - Segment select FSM
    - Linear interpolator datapath
    """

    if not points:
        raise ValueError("target curve points must be non-empty")
    # Sorting once guarantees monotonic time traversal during interpolation.
    points = sorted(points, key=lambda p: p[0])

    def target_f0_at_time(t_s: float) -> float:
        if t_s <= points[0][0]:
            return float(points[0][1])
        if t_s >= points[-1][0]:
            return float(points[-1][1])
        for (t0, f0), (t1, f1) in zip(points[:-1], points[1:]):
            if t0 <= t_s <= t1:
                if t1 == t0:
                    return float(f1)
                alpha = (t_s - t0) / (t1 - t0)
                return float((1.0 - alpha) * f0 + alpha * f1)
        return float(points[-1][1])

    return target_f0_at_time


def build_target_config_from_history(
    *,
    period_history: list[int],
    fs_hz: int,
    duration_s: float,
    target_hz: float | list[tuple[float, float]] | None,
) -> TargetConfig:
    """Resolve pitch target mode from estimated period history and user input.

    This function converts flexible user intent into one unified callable target:
    - `target_hz is None`: choose an internal preset curve based on base pitch.
    - `target_hz` scalar: use a constant absolute frequency.
    - `target_hz` list: use explicit control points (seconds or normalized time).
    """

    # Base f0 estimate comes from the robust median of observed periods.
    median_period = float(np.median(period_history))
    base_f0 = float(fs_hz) / median_period

    if target_hz is None:
        # QUICK TOGGLE: uncomment ONE preset block, keep others commented.

        # Preset A (default): lock to base pitch (flat target).
        points = [
            (0.0, base_f0),
            (duration_s, base_f0),
        ]

        # Preset B: lock to +2 semitones above base pitch.
        # up_2st = base_f0 * (2 ** (2 / 12))
        # points = [
        #     (0.0, up_2st),
        #     (duration_s, up_2st),
        # ]

        # Preset C: expressive contour (up then down then return).
        # up_2st = base_f0 * (2 ** (2 / 12))
        # down_2st = base_f0 * (2 ** (-2 / 12))
        # points = [
        #     (0.0, base_f0),
        #     (0.35 * duration_s, up_2st),
        #     (0.70 * duration_s, down_2st),
        #     (duration_s, base_f0),
        # ]

        return TargetConfig(
            target_f0_at_time=make_target_curve(points),
            selected_points=points,
            selected_const_hz=None,
        )

    if isinstance(target_hz, (int, float)):
        if float(target_hz) <= 0.0:
            raise ValueError("target_hz must be > 0")
        target_const = float(target_hz)

        def constant_target(_t_s: float) -> float:
            return float(target_const)

        return TargetConfig(
            target_f0_at_time=constant_target,
            selected_points=None,
            selected_const_hz=target_const,
        )

    if len(target_hz) == 0:
        raise ValueError("target_hz points must be non-empty")

    points = []
    for t_s, f_hz in target_hz:
        if f_hz <= 0.0:
            raise ValueError("target_hz point frequencies must be > 0")
        # Accept either absolute seconds or normalized timeline [0, 1].
        t_abs = float(t_s)
        if 0.0 <= t_abs <= 1.0 and duration_s > 0.0:
            t_abs *= duration_s
        points.append((t_abs, float(f_hz)))

    return TargetConfig(
        target_f0_at_time=make_target_curve(points),
        selected_points=points,
        selected_const_hz=None,
    )


def update_smoothed_period(period_n: int | None, est_period: int | None, smoothing: float) -> int | None:
    """Single-step period tracker smoothing.

    Equation: new = (1-a)*old + a*estimate where a=`smoothing`.
    This reduces jitter in epoch timing between adjacent analysis frames.
    """

    if est_period is None:
        return period_n
    if period_n is None:
        return int(est_period)
    return int(round((1.0 - smoothing) * period_n + smoothing * est_period))


def enqueue_grains_for_frame(
    *,
    input_signal: np.ndarray,
    n_samples: int,
    estimated_period: int | None,
    frame_start: int,
    frame_end: int,
    next_epoch_center: int,
    synth_start: int | None,
    grains: list[Grain],
)-> tuple[int, int | None]:
    """Generate epochs for one analysis frame and enqueue windowed grains.

    Inputs are explicit state values to keep this helper deterministic and
    friendly for eventual RTL partitioning.

    Returns updated:
    - next_epoch_center: next free-running epoch timestamp
    - synth_start: first synthesis center (initialized once)
    """

    if estimated_period is None or estimated_period <= 0:
        return next_epoch_center, synth_start

    # If epoch clock lags behind the current frame, fast-forward to frame start.
    if next_epoch_center < frame_start:
        k = (frame_start - next_epoch_center + estimated_period - 1) // estimated_period
        next_epoch_center += int(k) * estimated_period

    # Emit all epochs that land inside this frame and extract grains immediately.
    while next_epoch_center < frame_end:
        if 0 <= next_epoch_center < n_samples:
            raw = extract_grain_samples(input_signal, center=int(next_epoch_center), period=int(estimated_period))
            if raw.size > 0:
                grains.append(
                    Grain(
                        center=int(next_epoch_center),
                        period=int(estimated_period),
                        samples=raw * np.hanning(raw.size),
                    )
                )
                if synth_start is None:
                    # First valid epoch defines where synthesis begins.
                    synth_start = int(next_epoch_center)
        next_epoch_center += estimated_period

    return next_epoch_center, synth_start


def overlap_add_grain(output_signal: np.ndarray, grain: Grain, synth_center: int, n_samples: int) -> None:
    """Place one grain centered at `synth_center` and overlap-add into output.

    Overlap-add means multiple grains contribute to the same output samples.
    This is the core operation that reconstructs continuous audio.
    """

    period = int(grain.period)
    length = int(grain.samples.size)
    if length <= 0:
        return

    # Normal (ideal) output placement window for this grain center.
    # If output were unbounded, we'd write the full grain to [start, end).
    start = synth_center - period
    end = start + length

    # Clipped output window after enforcing valid output buffer bounds.
    # out_start/out_end are the actual write range into output_signal.
    out_start = max(0, start)
    out_end = min(n_samples, end)
    if out_end <= out_start:
        return

    ### Map clipped output span back into grain-local coordinates. ###

    # grain_start is the first grain index aligned with out_start in output.
    grain_start = out_start - start

    # grain_end is one-past-last grain index aligned with out_end in output.
    grain_end = grain_start + (out_end - out_start)
    output_signal[out_start:out_end] += grain.samples[grain_start:grain_end]


def compute_pitch_factor(
    *,
    period: int,
    fs_hz: int,
    use_target_curve: bool,
    target_f0_at_time: Callable[[float], float] | None,
    constant_pitch_factor: float,
    synth_center: int,
) -> float:
    """Compute per-grain pitch factor for either fixed or curve mode.

    Returned factor semantics:
    - >1.0: pitch up (denser synthesis placements)
    - <1.0: pitch down (sparser synthesis placements)
    """

    if period <= 0:
        return 1.0

    if not use_target_curve:
        # Constant transposition mode.
        factor = float(constant_pitch_factor)
        return factor if factor > 0.0 else 1.0

    if target_f0_at_time is None:
        return 1.0

    # Target-follow mode: compare desired f0(t) to current local f0.
    current_f0 = float(fs_hz) / float(period)
    target_f0 = float(target_f0_at_time(synth_center / float(fs_hz)))
    if current_f0 > 0.0 and target_f0 > 0.0:
        return target_f0 / current_f0
    return 1.0


def synthesize_chunk_from_grains(
    *,
    output_signal: np.ndarray,
    n_samples: int,
    chunk_end: int,
    synth_center: int,
    analysis_index: float,
    grains: list[Grain],
    fs_hz: int,
    use_target_curve: bool,
    target_f0_at_time: Callable[[float], float] | None,
    constant_pitch_factor: float,
) -> tuple[int, float]:
    """Synthesize one output chunk from currently available grains.

    Stateful cursors:
    - synth_center: output timeline cursor (where next grain center lands)
    - analysis_index: fractional pointer into analysis grains

    This function is intentionally chunk-bounded to emulate realtime operation.
    """

    # Process synthesis events until this chunk boundary is reached.
    while synth_center < chunk_end:
        last_idx = len(grains) - 1
        # Fractional analysis pointer enables non-integer rate conversion.
        i = int(analysis_index)
        if i < 0:
            i = 0
        if i > last_idx:
            i = last_idx

        grain = grains[i]
        period = int(grain.period)

        overlap_add_grain(output_signal=output_signal, grain=grain, synth_center=synth_center, n_samples=n_samples)
        pitch_factor = compute_pitch_factor(
            period=period,
            fs_hz=fs_hz,
            use_target_curve=use_target_curve,
            target_f0_at_time=target_f0_at_time,
            constant_pitch_factor=constant_pitch_factor,
            synth_center=synth_center,
        )

        # Hop rule: hop_out ~= T / pitch_factor.
        synth_hop = max(1, int(round(period / pitch_factor)))
        synth_center += synth_hop
        # Keep analysis pointer in reciprocal proportion.
        analysis_index += 1.0 / pitch_factor

    return synth_center, analysis_index


def run_pass_through(
    input_pcm: str,
    output_pcm: str,
    output_wav: str,
    *,
    FS_HZ: int = 48000,
    START_S: float = 0.0,
    END_S: float | None = None,
    USE_TARGET_CURVE: bool = True,
    CONSTANT_PITCH_FACTOR: float = 2 ** (2 / 12),
    TARGET_HZ: float | list[tuple[float, float]] | None = None,
    CHUNK_SIZE: int = 512,
    WINDOW_SIZE: int = 1024,
    HOP_SIZE: int = 256,
    FMIN_HZ: float = 80.0,
    FMAX_HZ: float = 1000.0,
    LPF_FC_HZ: float = 0.0,
    CLIP_RATIO: float = 0.30,
    THRESHOLD_RATIO: float = 0.2,
    SMOOTHING: float = 0.2,
) -> np.ndarray:
    """Top-level streaming-style TD-PSOLA pipeline.

    High-level stages inside each chunk iteration:
    1. Analysis: run autocorrelation on any newly available frames.
    2. Epoch/grain build: generate new epochs and enqueue windowed grains.
    3. Target setup: initialize target f0(t) once enough history exists. (optional)
    4. Synthesis: overlap-add grains until the chunk boundary.

    Even though this is an offline script, the global chunk loop mirrors
    realtime control flow and state management.
    """

    # Stage 0: input acquisition.
    input_signal = read_pcm_f32(input_pcm, fs_hz=FS_HZ, start_s=START_S, end_s=END_S)
    if input_signal.size == 0:
        raise SystemExit("empty input")

    if CHUNK_SIZE <= 0:
        raise ValueError("chunk_size must be > 0")

    n_samples = int(input_signal.size)

    # Output accumulation buffer written by overlap-add synthesis.
    output_signal = np.zeros(n_samples, dtype=np.float64)

    # All windowed grains discovered so far.
    # Needed because synthesis can lag behind analysis and still reference older grains.
    grains: list[Grain] = []

    # Running history of accepted period estimates.
    # Needed to derive stable base_f0 (median period) for target preset initialization.
    period_history: list[int] = []
    

    ### Analysis-plane state.#####################

    # Current smoothed period estimate T (samples), updated each analysis frame.
    # Needed to suppress frame-to-frame jitter before epoch scheduling.
    estimated_period: int | None = None

    # Absolute timestamp of the next free-running epoch.
    # Needed so epoch generation continues seamlessly across chunk boundaries.
    next_epoch_center = 0

    # Start index of next analysis frame to process.
    # Needed to avoid reprocessing old frames and to preserve stream progression.
    frame_start = 0
    ##########################################
    


    ### Synthesis-plane state. ##################

    # Fractional pointer into analysis grains (can be non-integer for rate conversion).
    # Needed to decouple analysis timeline from synthesis timeline during pitch shifting.
    analysis_index = 0.0

    # Absolute output sample index where next grain center is placed.
    # Needed to continue overlap-add placement continuously across chunks.
    synth_center: int | None = None
    ##########################################

    # Total signal duration used for normalized target-time conversion.
    duration_s = n_samples / float(FS_HZ)

    # Callable target f0(t) built once when enough history is available.
    # Kept as state so later chunks reuse the same target definition.
    target_f0_at_time: Callable[[float], float] | None = None

    # Debug/telemetry copy of the selected target curve points.
    # Needed only for informative printout after synthesis.
    selected_target_points: list[tuple[float, float]] | None = None

    # Debug/telemetry copy when a constant-Hz target was selected.
    # Needed only for informative printout after synthesis.
    selected_target_const: float | None = None

    # Global scheduler: emulate realtime by moving across fixed-size chunks.
    for chunk_start in tqdm(range(0, n_samples, CHUNK_SIZE)):
        chunk_end = min(n_samples, chunk_start + CHUNK_SIZE)
        # Permit analysis to look slightly ahead so frame windows are complete.
        analysis_limit = min(n_samples, chunk_end + WINDOW_SIZE)

        # Stage 1: analysis for any new frames now available.
        while frame_start + WINDOW_SIZE <= analysis_limit:
            frame = input_signal[frame_start:frame_start + WINDOW_SIZE]
            _f0_hz, est_period = ac.estimate_f0_autocorr(
                frame,
                fs_hz=float(FS_HZ),
                fmin_hz=FMIN_HZ,
                fmax_hz=FMAX_HZ,
                lpf_fc_hz=LPF_FC_HZ,
                clip_ratio=CLIP_RATIO,
                threshold_ratio=THRESHOLD_RATIO,
                use_hann=True,
            )
            estimated_period = update_smoothed_period(
                period_n=estimated_period,
                est_period=est_period,
                smoothing=SMOOTHING,
            )

            if estimated_period is not None and estimated_period > 0:
                period_history.append(int(estimated_period))
                frame_end = frame_start + WINDOW_SIZE
                # Stage 2: epoch generation + grain enqueue for this frame.
                next_epoch_center, synth_center = enqueue_grains_for_frame(
                    input_signal=input_signal,
                    n_samples=n_samples,
                    estimated_period=estimated_period,
                    frame_start=frame_start,
                    frame_end=frame_end,
                    next_epoch_center=next_epoch_center,
                    synth_start=synth_center,
                    grains=grains,
                )

            frame_start += HOP_SIZE

        # Stage 3: lazily initialize target curve once pitch history exists. (optional)
        if USE_TARGET_CURVE and target_f0_at_time is None and period_history:
            target_cfg = build_target_config_from_history(
                period_history=period_history,
                fs_hz=FS_HZ,
                duration_s=duration_s,
                target_hz=TARGET_HZ,
            )
            target_f0_at_time = target_cfg.target_f0_at_time
            selected_target_points = target_cfg.selected_points
            selected_target_const = target_cfg.selected_const_hz

        # Until first grain exists, synthesis cannot run.
        if synth_center is None or not grains:
            continue

        # Stage 4: synthesize only up to this chunk boundary.
        synth_center, analysis_index = synthesize_chunk_from_grains(
            output_signal=output_signal,
            n_samples=n_samples,
            chunk_end=chunk_end,
            synth_center=synth_center,
            analysis_index=analysis_index,
            grains=grains,
            fs_hz=FS_HZ,
            use_target_curve=USE_TARGET_CURVE,
            target_f0_at_time=target_f0_at_time,
            constant_pitch_factor=CONSTANT_PITCH_FACTOR,
        )

    if not grains:
        raise RuntimeError("no epochs/grains found")

    if USE_TARGET_CURVE:
        print("mode: target curve")
        if selected_target_points is not None:
            print("target curve (Hz):", selected_target_points)
        elif selected_target_const is not None:
            print("target: constant Hz:", selected_target_const)
    else:
        print("mode: constant pitch factor")
        print("constant pitch factor:", CONSTANT_PITCH_FACTOR)

    print("epochs:", len(grains), "grains:", len(grains))

    # Final output formatting/sink stage.
    write_pcm_f32(output_pcm, output_signal)
    write_wav_int16(output_wav, output_signal, fs_hz=FS_HZ)
    print("wrote:", output_pcm)
    print("wrote:", output_wav)

    return output_signal


if __name__ == "__main__":
    FS_HZ = 48000
    # INPUT_PCM = "twinkle.pcm"
    INPUT_PCM = "DAZBEE_Acapella.pcm"

    base, _ext = os.path.splitext(INPUT_PCM)
    OUTPUT_PCM = f"{base}_psola4_target.pcm"
    OUTPUT_WAV = f"{base}_psola4_target.wav"

    # Easy mode toggle:
    # True  -> target-based autotune (uses target presets in run_pass_through)
    # False -> constant transposition using constant_pitch_factor
    USE_TARGET_CURVE = False
    # Example: +2 semitones for constant mode.
    CONSTANT_PITCH_FACTOR = 2 ** (2 / 12)

    run_pass_through(
        input_pcm=INPUT_PCM,
        output_pcm=OUTPUT_PCM,
        output_wav=OUTPUT_WAV,
        FS_HZ=FS_HZ,
        START_S=0.0,
        END_S=None,
        USE_TARGET_CURVE=USE_TARGET_CURVE,
        CONSTANT_PITCH_FACTOR=CONSTANT_PITCH_FACTOR,
    )
