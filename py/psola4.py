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
    center: int
    period: int
    samples: np.ndarray


@dataclass
class TargetConfig:
    target_f0_at_time: Callable[[float], float]
    selected_points: list[tuple[float, float]] | None
    selected_const_hz: float | None


def read_pcm_f32(path: str, fs_hz: int, start_s: float = 0.0, end_s: float | None = None) -> np.ndarray:
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
    start = max(0, min(start, samples_f32.size))
    end = max(start, min(end, samples_f32.size))
    return samples_f32[start:end].astype(np.float64, copy=False)


def write_pcm_f32(path: str, signal: np.ndarray) -> None:
    signal_f32 = np.asarray(signal, dtype=np.float32)
    signal_f32.tofile(path)


def write_wav_int16(path: str, signal: np.ndarray, fs_hz: int) -> None:
    if signal.size == 0:
        return
    signal_f64 = np.asarray(signal, dtype=np.float64)
    signal_clipped = np.clip(signal_f64, -1.0, 1.0)
    signal_i16 = (signal_clipped * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(int(fs_hz))
        wf.writeframes(signal_i16.tobytes())


def extract_grain_samples(signal: np.ndarray, center: int, period: int) -> np.ndarray:
    length = 2 * int(period)
    if length <= 0:
        return np.zeros(0, dtype=np.float64)

    grain = np.zeros(length, dtype=np.float64)
    start = center - period
    end = center + period

    src_start = max(0, start)
    src_end = min(len(signal), end)
    if src_end > src_start:
        dst_start = src_start - start
        dst_end = dst_start + (src_end - src_start)
        grain[dst_start:dst_end] = signal[src_start:src_end]

    return grain


def make_target_curve(points: list[tuple[float, float]]):
    if not points:
        raise ValueError("target curve points must be non-empty")
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
    if estimated_period is None or estimated_period <= 0:
        return next_epoch_center, synth_start

    if next_epoch_center < frame_start:
        k = (frame_start - next_epoch_center + estimated_period - 1) // estimated_period
        next_epoch_center += int(k) * estimated_period

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
                    synth_start = int(next_epoch_center)
        next_epoch_center += estimated_period

    return next_epoch_center, synth_start


def overlap_add_grain(output_signal: np.ndarray, grain: Grain, synth_center: int, n_samples: int) -> None:
    period = int(grain.period)
    length = int(grain.samples.size)
    if length <= 0:
        return

    start = synth_center - period
    end = start + length
    out_start = max(0, start)
    out_end = min(n_samples, end)
    if out_end <= out_start:
        return

    grain_start = out_start - start
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
    if period <= 0:
        return 1.0

    if not use_target_curve:
        factor = float(constant_pitch_factor)
        return factor if factor > 0.0 else 1.0

    if target_f0_at_time is None:
        return 1.0

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
    while synth_center < chunk_end:
        last_idx = len(grains) - 1
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

        synth_hop = max(1, int(round(period / pitch_factor)))
        synth_center += synth_hop
        analysis_index += 1.0 / pitch_factor

    return synth_center, analysis_index


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
    target_hz: float | list[tuple[float, float]] | None = None,
    chunk_size: int = 512,
    window_size: int = 1024,
    hop_size: int = 256,
    fmin_hz: float = 80.0,
    fmax_hz: float = 1000.0,
    lpf_fc_hz: float = 0.0,
    clip_ratio: float = 0.30,
    threshold_ratio: float = 0.2,
    smoothing: float = 0.2,
) -> np.ndarray:
    input_signal = read_pcm_f32(input_pcm, fs_hz=fs_hz, start_s=start_s, end_s=end_s)
    if input_signal.size == 0:
        raise SystemExit("empty input")

    if chunk_size <= 0:
        raise ValueError("chunk_size must be > 0")

    n_samples = int(input_signal.size)
    output_signal = np.zeros(n_samples, dtype=np.float64)

    grains: list[Grain] = []
    period_history: list[int] = []

    estimated_period: int | None = None
    next_epoch_center = 0
    frame_start = 0

    analysis_index = 0.0
    synth_center: int | None = None

    duration_s = n_samples / float(fs_hz)
    target_f0_at_time: Callable[[float], float] | None = None
    selected_target_points: list[tuple[float, float]] | None = None
    selected_target_const: float | None = None

    for chunk_start in tqdm(range(0, n_samples, chunk_size)):
        chunk_end = min(n_samples, chunk_start + chunk_size)
        analysis_limit = min(n_samples, chunk_end + window_size)

        while frame_start + window_size <= analysis_limit:
            frame = input_signal[frame_start:frame_start + window_size]
            _f0_hz, est_period = ac.estimate_f0_autocorr(
                frame,
                fs_hz=float(fs_hz),
                fmin_hz=fmin_hz,
                fmax_hz=fmax_hz,
                lpf_fc_hz=lpf_fc_hz,
                clip_ratio=clip_ratio,
                threshold_ratio=threshold_ratio,
                use_hann=True,
            )
            estimated_period = update_smoothed_period(
                period_n=estimated_period,
                est_period=est_period,
                smoothing=smoothing,
            )

            if estimated_period is not None and estimated_period > 0:
                period_history.append(int(estimated_period))
                frame_end = frame_start + window_size
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

            frame_start += hop_size

        if use_target_curve and target_f0_at_time is None and period_history:
            target_cfg = build_target_config_from_history(
                period_history=period_history,
                fs_hz=fs_hz,
                duration_s=duration_s,
                target_hz=target_hz,
            )
            target_f0_at_time = target_cfg.target_f0_at_time
            selected_target_points = target_cfg.selected_points
            selected_target_const = target_cfg.selected_const_hz

        if synth_center is None or not grains:
            continue

        synth_center, analysis_index = synthesize_chunk_from_grains(
            output_signal=output_signal,
            n_samples=n_samples,
            chunk_end=chunk_end,
            synth_center=synth_center,
            analysis_index=analysis_index,
            grains=grains,
            fs_hz=fs_hz,
            use_target_curve=use_target_curve,
            target_f0_at_time=target_f0_at_time,
            constant_pitch_factor=constant_pitch_factor,
        )

    if not grains:
        raise RuntimeError("no epochs/grains found")

    if use_target_curve:
        print("mode: target curve")
        if selected_target_points is not None:
            print("target curve (Hz):", selected_target_points)
        elif selected_target_const is not None:
            print("target: constant Hz:", selected_target_const)
    else:
        print("mode: constant pitch factor")
        print("constant pitch factor:", constant_pitch_factor)

    print("epochs:", len(grains), "grains:", len(grains))

    write_pcm_f32(output_pcm, output_signal)
    write_wav_int16(output_wav, output_signal, fs_hz=fs_hz)
    print("wrote:", output_pcm)
    print("wrote:", output_wav)

    return output_signal


if __name__ == "__main__":
    fs_hz = 48000
    input_pcm = "twinkle.pcm"

    base, _ext = os.path.splitext(input_pcm)
    output_pcm = f"{base}_psola4_target.pcm"
    output_wav = f"{base}_psola4_target.wav"

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
