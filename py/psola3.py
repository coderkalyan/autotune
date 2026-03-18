"""Streaming-friendly TD-PSOLA with time-varying target frequency.

This prototype mirrors the RTL-oriented architecture:
- sliding autocorrelation to estimate period T
- free-running epochs
- 2T Hann-windowed grains queued and overlap-added at epoch centers
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
    center: int
    period: int
    samples: np.ndarray


def read_pcm_f32(path: str, fs_hz: int, start_s: float = 0.0, end_s: float | None = None) -> np.ndarray:
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
    start = max(0, min(start, x.size))
    end = max(start, min(end, x.size))
    return x[start:end].astype(np.float64, copy=False)


def write_pcm_f32(path: str, y: np.ndarray) -> None:
    y_f32 = np.asarray(y, dtype=np.float32)
    y_f32.tofile(path)


def write_wav_int16(path: str, y: np.ndarray, fs_hz: int) -> None:
    if y.size == 0:
        return
    y_f64 = np.asarray(y, dtype=np.float64)
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
    x = np.asarray(signal, dtype=np.float64)
    if x.size == 0:
        return []

    epochs: list[tuple[int, int]] = []
    period_n: int | None = None
    next_epoch = 0

    for frame_start in tqdm(range(0, x.size - window_size + 1, hop_size)):
        frame = x[frame_start:frame_start + window_size]
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

        if est_period is not None:
            if period_n is None:
                period_n = int(est_period)
            else:
                period_n = int(round((1.0 - smoothing) * period_n + smoothing * est_period))

        if period_n is None or period_n <= 0:
            continue

        frame_end = frame_start + window_size
        if next_epoch < frame_start:
            k = (frame_start - next_epoch + period_n - 1) // period_n
            next_epoch += int(k) * period_n

        while next_epoch < frame_end:
            if 0 <= next_epoch < x.size:
                epochs.append((int(next_epoch), int(period_n)))
            next_epoch += period_n

    return epochs


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


def build_grain_queue(
    signal: np.ndarray,
    epochs: list[tuple[int, int]],
) -> tuple[list[np.ndarray], list[Grain]]:
    sample_buffer: list[np.ndarray] = []
    grains: list[Grain] = []

    for center, period in tqdm(epochs):
        raw = extract_grain_samples(signal, center=center, period=period)
        if raw.size == 0:
            continue
        sample_buffer.append(raw)

        window = np.hanning(raw.size)
        windowed = raw * window
        grains.append(Grain(center=center, period=period, samples=windowed))

    return sample_buffer, grains


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


def synthesize_pitch_shift(
    grains: list[Grain],
    n_samples: int,
    *,
    fs_hz: float,
    target_f0_at_time,
) -> np.ndarray:
    y = np.zeros(int(n_samples), dtype=np.float64)
    if not grains:
        return y

    ai = 0.0
    s = int(grains[0].center)
    last_idx = len(grains) - 1

    while s < n_samples:
        i = int(ai)
        if i < 0:
            i = 0
        if i > last_idx:
            i = last_idx

        grain = grains[i]
        period = int(grain.period)
        length = int(grain.samples.size)
        if length > 0:
            start = s - period
            end = start + length
            out_start = max(0, start)
            out_end = min(n_samples, end)
            if out_end > out_start:
                g_start = out_start - start
                g_end = g_start + (out_end - out_start)
                y[out_start:out_end] += grain.samples[g_start:g_end]

        if period <= 0:
            pitch_factor = 1.0
        else:
            current_f0 = float(fs_hz) / float(period)
            target_f0 = float(target_f0_at_time(s / float(fs_hz)))
            if current_f0 > 0.0 and target_f0 > 0.0:
                pitch_factor = target_f0 / current_f0
                # print(target_f0, current_f0, pitch_factor)
            else:
                pitch_factor = 1.0

        synth_hop = max(1, int(round(period / pitch_factor)))
        s += synth_hop
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
    target_points_hz: list[tuple[float, float]] | None = None,
) -> np.ndarray:
    x = read_pcm_f32(input_pcm, fs_hz=fs_hz, start_s=start_s, end_s=end_s)
    if x.size == 0:
        raise SystemExit("empty input")

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

    sample_buffer, grains = build_grain_queue(x, epochs)
    print("epochs:", len(epochs), "grains:", len(sample_buffer))

    duration_s = x.size / float(fs_hz)
    periods = [p for _c, p in epochs if p > 0]
    if not periods:
        raise RuntimeError("no valid periods for target curve")
    median_period = float(np.median(periods))
    base_f0 = float(fs_hz) / median_period

    # target_points_hz = [(0.0, base_f0 * 6 ** (2 / 12))]
    target_points_hz = []
    for i in range(10):
        target_points_hz.append((i / 10.0, base_f0 * (2 ** (i / 12))))

    if target_points_hz is None:
        up_2st = base_f0 * (2 ** (2 / 12))
        down_2st = base_f0 * (2 ** (-2 / 12))
        target_points_hz = [
            (0.0, base_f0),
            (0.35 * duration_s, up_2st),
            (0.70 * duration_s, down_2st),
            (duration_s, base_f0),
        ]

    target_f0_at_time = make_target_curve(target_points_hz)
    print("target curve (Hz):", target_points_hz)

    y = synthesize_pitch_shift(
        grains,
        n_samples=x.size,
        fs_hz=float(fs_hz),
        target_f0_at_time=target_f0_at_time,
    )

    write_pcm_f32(output_pcm, y)
    write_wav_int16(output_wav, y, fs_hz=fs_hz)
    print("wrote:", output_pcm)
    print("wrote:", output_wav)

    return y


if __name__ == "__main__":
    fs_hz = 48000
    input_pcm = "twinkle.pcm"

    base, _ext = os.path.splitext(input_pcm)
    output_pcm = f"{base}_psola3_target.pcm"
    output_wav = f"{base}_psola3_target.wav"

    run_pass_through(
        input_pcm=input_pcm,
        output_pcm=output_pcm,
        output_wav=output_wav,
        fs_hz=fs_hz,
        start_s=0.0,
        end_s=None,
    )
