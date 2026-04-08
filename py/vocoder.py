"""Simple time-domain channel vocoder demo.

Usage: python vocoder.py input.pcm output.pcm

Reads raw float32 PCM (mono) at FS_HZ, vocodes it against a sawtooth carrier
of fundamental F0_HZ, and writes float32 PCM out. All filtering is done in the
time domain with biquad bandpass + lowpass filters (no FFT).
"""

import sys
import numpy as np
from scipy.signal import butter, sosfilt

# ---- configurable constants ----
FS_HZ = 48000           # sample rate of input/output PCM
F0_HZ = 440.0           # carrier fundamental frequency
N_HARMONICS = 24        # sawtooth harmonics in carrier
N_BANDS = 32            # number of vocoder bands
F_LO_HZ = 100.0         # low edge of band range
F_HI_HZ = 8000.0        # high edge of band range
ENV_CUTOFF_HZ = 30.0    # envelope follower LPF cutoff
BP_ORDER = 2            # biquad => order 2
ENV_ORDER = 2
OUTPUT_GAIN = 1.0

# carrier flavor
CHORUS_DETUNE_CENTS = 5.0   # +/- detune for the two extra sawtooths
NOISE_LEVEL = 0.005         # white noise mixed into carrier
# delay-based chorus/reverb taps: list of (delay_seconds, gain)
FX_TAPS = [(0.017, 0.45), (0.029, 0.35), (0.053, 0.25), (0.091, 0.18)]
FX_WET = 0.35


def read_pcm_f32(path: str) -> np.ndarray:
    with open(path, "rb") as f:
        return np.frombuffer(f.read(), dtype=np.float32)


def write_pcm_f32(path: str, y: np.ndarray) -> None:
    np.asarray(y, dtype=np.float32).tofile(path)


def make_sawtooth(n: int, fs: int, f0: float, n_harm: int) -> np.ndarray:
    """Additive sawtooth: sum of sin(2 pi k f0 t) / k for k=1..n_harm."""
    t = np.arange(n) / fs
    out = np.zeros(n, dtype=np.float64)
    for k in range(1, n_harm + 1):
        if k * f0 >= fs / 2:
            break
        out += np.sin(2.0 * np.pi * k * f0 * t) / k
    # normalize roughly to [-1, 1]
    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out


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

    # carrier: detuned 3-saw chorus + a touch of white noise
    detune = 2.0 ** (CHORUS_DETUNE_CENTS / 1200.0)
    carrier = (
        make_sawtooth(n, FS_HZ, F0_HZ, N_HARMONICS)
        + make_sawtooth(n, FS_HZ, F0_HZ * detune, N_HARMONICS)
        + make_sawtooth(n, FS_HZ, F0_HZ / detune, N_HARMONICS)
    ) / 3.0
    rng = np.random.default_rng(0)
    carrier = carrier + NOISE_LEVEL * rng.standard_normal(n)

    # simple delay-based chorus/reverb on the carrier
    wet = np.zeros(n, dtype=np.float64)
    for delay_s, gain in FX_TAPS:
        d = int(delay_s * FS_HZ)
        if 0 < d < n:
            wet[d:] += gain * carrier[:-d]
    carrier = carrier + FX_WET * wet

    # harmonic frequencies for assigning carrier energy to bands
    harm_freqs = np.array([k * F0_HZ for k in range(1, N_HARMONICS + 1)])

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
        env = sosfilt(env_sos, np.abs(band)) * 64

        # bandpass the carrier the same way so this band only contributes
        # carrier energy whose harmonics fall inside [f1, f2]
        carrier_band = sosfilt(bp_sos, carrier)

        out += carrier_band * env

        # (harm_freqs unused directly; bandpassing the carrier achieves the
        # "which harmonics belong to which band" mapping naturally.)
        _ = harm_freqs

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
