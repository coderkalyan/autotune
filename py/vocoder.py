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
OUTPUT_GAIN = 2.0

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

import numpy as np

# ---------- wavetable generation (done once) ----------

TABLE_SIZE = 4096

def _build_table(num_harmonics: int, alpha: float) -> np.ndarray:
    """One cycle, hybrid (1/k)*exp(-α(k-1)) profile."""
    phase = np.linspace(0, 2 * np.pi, TABLE_SIZE, endpoint=False)
    out = np.zeros(TABLE_SIZE, dtype=np.float64)
    for k in range(1, num_harmonics + 1):
        out += (1.0 / k) * np.exp(-alpha * (k - 1)) * np.sin(k * phase)
    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out

# mipmap levels: (max_harmonics, max_f0 this level is safe for)
# "safe" means max_harmonic * f0 < fs/2
_MIPMAP_SPEC = [
    (96,  250.0),   # level 0: up to ~250 Hz fundamental
    (48,  500.0),   # level 1: up to ~500 Hz
    (24,  1000.0),  # level 2: up to ~1000 Hz
    (12,  2000.0),  # level 3: fallback
]

def build_wavetable_bank(alpha: float = 0.08) -> list[np.ndarray]:
    """Pre-compute mipmap levels for one timbre. Returns list of tables."""
    return [_build_table(spec[0], alpha) for spec in _MIPMAP_SPEC]


# ---------- runtime oscillator ----------

def _select_mipmap(f0: float) -> int:
    """Pick the richest mipmap level that won't alias at this f0."""
    for i, (_, max_f0) in enumerate(_MIPMAP_SPEC):
        if f0 <= max_f0:
            return i
    return len(_MIPMAP_SPEC) - 1

def _read_table_lerp(table: np.ndarray, phase: np.ndarray) -> np.ndarray:
    """Read from wavetable with linear interpolation. Phase is in [0, 1)."""
    pos = phase * TABLE_SIZE
    idx = pos.astype(np.int64)
    frac = pos - idx
    idx0 = idx % TABLE_SIZE
    idx1 = (idx + 1) % TABLE_SIZE
    return table[idx0] + frac * (table[idx1] - table[idx0])

def make_carrier(n: int, fs: int, f0: float,
                 alpha: float = 0.08,
                 detune_cents: float = 4.0,
                 bank: list[np.ndarray] | None = None) -> np.ndarray:
    """
    Synthesise a vocoder carrier tone.

    Drop-in replacement for make_sawtooth(n, fs, f0, n_harm).

    Parameters
    ----------
    n       : number of output samples
    fs      : sample rate (e.g. 48000)
    f0      : fundamental frequency in Hz
    alpha   : harmonic rolloff (0.03=bright, 0.08=warm, 0.15=mellow)
    detune_cents : unison detune spread (± cents). 0 = single osc.
    bank    : pre-built wavetable bank (if None, built on the fly)

    Returns
    -------
    np.ndarray of shape (n,), normalized to [-1, 1]
    """
    if bank is None:
        bank = build_wavetable_bank(alpha)

    table = bank[_select_mipmap(f0)]

    # two detuned oscillators
    detune_ratio = 2.0 ** (detune_cents / 1200.0)
    f_lo = f0 / detune_ratio
    f_hi = f0 * detune_ratio

    t = np.arange(n, dtype=np.float64) / fs

    phase_lo = (f_lo * t) % 1.0
    phase_hi = (f_hi * t) % 1.0

    out = 0.5 * _read_table_lerp(table, phase_lo) + \
          0.5 * _read_table_lerp(table, phase_hi)

    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out

# ---------- chord helper ----------

def make_chord(n: int, fs: int, freqs: list[float],
               alpha: float = 0.08,
               detune_cents: float = 4.0) -> np.ndarray:
    """
    Mix multiple carrier voices into a chord.

    Parameters
    ----------
    freqs : list of fundamental frequencies (up to 5 voices)

    Returns
    -------
    np.ndarray of shape (n,), normalized to [-1, 1]
    """
    bank = build_wavetable_bank(alpha)
    out = np.zeros(n, dtype=np.float64)
    for f0 in freqs:
        out += make_carrier(n, fs, f0, alpha, detune_cents, bank)
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
    # detune = 2.0 ** (CHORUS_DETUNE_CENTS / 1200.0)
    # carrier = (
    #     make_sawtooth(n, FS_HZ, F0_HZ, N_HARMONICS)
    #     + make_sawtooth(n, FS_HZ, F0_HZ * detune, N_HARMONICS)
    #     + make_sawtooth(n, FS_HZ, F0_HZ / detune, N_HARMONICS)
    # ) / 3.0
    # rng = np.random.default_rng(0)
    # carrier = carrier + NOISE_LEVEL * rng.standard_normal(n)
    # carrier = make_carrier(n, FS_HZ, F0_HZ)
    carrier = make_chord(n=n, fs=FS_HZ, freqs=[130.81, 164.81, 196.00], alpha=0.03)

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
        env = sosfilt(env_sos, np.abs(band)) * 128 # 64

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
