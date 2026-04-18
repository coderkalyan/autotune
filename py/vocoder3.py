"""Simple time-domain channel vocoder demo.

Usage: python vocoder.py input.pcm output.pcm

Reads raw float32 PCM (mono) at FS_HZ, vocodes it against an organ carrier
and writes float32 PCM out. All filtering is done in the time domain with
biquad bandpass + lowpass filters (no FFT).
"""

import sys
import numpy as np
from scipy.signal import butter, sosfilt

# ---- configurable constants ----
FS_HZ = 48000           # sample rate of input/output PCM
F0_HZ = 440.0           # carrier fundamental frequency
N_BANDS = 64            # number of vocoder bands
F_LO_HZ = 100.0         # low edge of band range
F_HI_HZ = 8000.0        # high edge of band range
ENV_CUTOFF_HZ = 30.0    # envelope follower LPF cutoff
BP_ORDER = 2            # biquad => order 2
ENV_ORDER = 2
OUTPUT_GAIN = 2.0

# delay-based chorus/reverb taps: list of (delay_seconds, gain)
FX_TAPS = [(0.017, 0.45), (0.029, 0.35), (0.053, 0.25), (0.091, 0.18)]
FX_WET = 0.35


def read_pcm_f32(path: str) -> np.ndarray:
    with open(path, "rb") as f:
        return np.frombuffer(f.read(), dtype=np.float32)


def write_pcm_f32(path: str, y: np.ndarray) -> None:
    np.asarray(y, dtype=np.float32).tofile(path)


def make_organ_carrier(n: int, fs: int, f0: float) -> np.ndarray:
    """Mellow gospel-registration organ carrier with maj9 voicing and
    5-voice unison detune per note."""
    # Mellow drawbars (dipped mids, moderate top)
    drawbars = [8, 5, 8, 4, 6, 5, 3, 5, 4]
    ratios = [0.5, 1.5, 1, 2, 3, 4, 5, 6, 8]

    # Maj9 voicing with sub-octaves and fills
    chord = [0.125, 0.25, 0.375, 0.5, 0.75, 1.0, 1.125, 1.25, 1.5, 2.0]
    amps  = [0.6,   0.8,  0.5,   0.9, 0.6,  1.0, 0.4,   0.5,  0.6, 0.35]

    # 5-voice ensemble detune per note (cents)
    detunes_cents = [-7, -3, 0, 3, 7]

    freqs = [f0 * r for r in chord]
    t = np.arange(n, dtype=np.float64) / fs
    sig = np.zeros(n, dtype=np.float64)

    for f, amp in zip(freqs, amps):
        for dc in detunes_cents:
            fd = f * (2 ** (dc / 1200))
            voice = sum((d / 8) * np.sin(2 * np.pi * fd * r * t)
                        for d, r in zip(drawbars, ratios))
            sig += voice * amp / len(detunes_cents)

    peak = np.max(np.abs(sig))
    if peak > 0:
        sig /= peak
    return sig


def log_band_edges(n_bands: int, f_lo: float, f_hi: float) -> np.ndarray:
    return np.geomspace(f_lo, f_hi, n_bands + 1)


def main(in_path: str, out_path: str) -> None:
    x = read_pcm_f32(in_path)
    n = x.size
    if n == 0:
        write_pcm_f32(out_path, x)
        return

    edges = log_band_edges(N_BANDS, F_LO_HZ, F_HI_HZ)
    centers = np.sqrt(edges[:-1] * edges[1:])  # geometric centers

    # envelope LPF (shared design)
    env_sos = butter(ENV_ORDER, ENV_CUTOFF_HZ, btype="low", fs=FS_HZ, output="sos")

    # carrier: organ
    carrier = make_organ_carrier(n, FS_HZ, F0_HZ)

    # simple delay-based chorus/reverb on the carrier
    wet = np.zeros(n, dtype=np.float64)
    for delay_s, gain in FX_TAPS:
        d = int(delay_s * FS_HZ)
        if 0 < d < n:
            wet[d:] += gain * carrier[:-d]
    carrier = carrier + FX_WET * wet

    out = np.zeros(n, dtype=np.float64)

    for b in range(N_BANDS):
        f1, f2 = edges[b], edges[b + 1]
        if f2 >= FS_HZ / 2:
            f2 = FS_HZ / 2 - 1.0
        if f1 >= f2:
            continue

        # bandpass the input to extract this band
        bp_sos = butter(BP_ORDER, [f1, f2], btype="band", fs=FS_HZ, output="sos")
        band = sosfilt(bp_sos, x)

        # envelope follower: rectify + LPF
        env = sosfilt(env_sos, np.abs(band)) * 128

        # bandpass the carrier the same way so this band only contributes
        # carrier energy whose harmonics fall inside [f1, f2]
        carrier_band = sosfilt(bp_sos, carrier)

        out += carrier_band * env

    # normalize
    peak = np.max(np.abs(out))
    if peak > 0:
        out = out / peak * OUTPUT_GAIN

    write_pcm_f32(out_path, out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python vocoder.py input.pcm output.pcm", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
