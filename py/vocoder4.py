"""Simple time-domain channel vocoder demo.

Usage: python vocoder.py input.pcm output.pcm

Reads raw float32 PCM (mono) at FS_HZ, vocodes it against a C-major chord
carrier. All filtering is done in the time domain with biquad filters (no FFT).

Algorithm overview (per band):
    input -> [BP -> |·| -> LP] -> env  x  [carrier -> BP] -> sum -> output
Each band's envelope modulates the same frequency slice of the carrier, so the
carrier's harmonic energy is shaped to match the input's spectral contour.
"""

import sys
import numpy as np
from scipy.signal import butter, sosfilt
import matplotlib.pyplot as plt
from tqdm import tqdm

FS_HZ = 48000
N_BANDS = 32  # more bands = better spectral resolution but more CPU
# F_LO_HZ = 100.0  # below ~100 Hz vocoder effect is barely audible
F_LO_HZ = 300.0  # below ~100 Hz vocoder effect is barely audible
F_HI_HZ = 8000.0  # above ~8 kHz mostly noise/sibilance; can be raised
BP_ORDER = 2  # order-2 biquad; raise to 4 for sharper band separation

# ---- wavetable constants ----
TABLE_SIZE = 4096  # one full oscillator cycle; larger = less interpolation error


def read_pcm_f32(path: str) -> np.ndarray:
    with open(path, "rb") as f:
        return np.frombuffer(f.read(), dtype=np.float32)


def write_pcm_f32(path: str, y: np.ndarray) -> None:
    np.asarray(y, dtype=np.float32).tofile(path)


def _build_table(num_harmonics: int, alpha: float) -> np.ndarray:
    """Build one wavetable cycle with a (1/k)*exp(-a(k-1)) harmonic profile.

    Pure 1/k gives a bright sawtooth; the exp(-a(k-1)) rolloff softens high
    harmonics. alpha=0.03 is bright, 0.08 is warm, 0.15 is mellow.
    """
    phase = np.linspace(0, 2 * np.pi, TABLE_SIZE, endpoint=False)
    out = np.zeros(TABLE_SIZE, dtype=np.float64)
    for k in range(1, num_harmonics + 1):
        out += (1.0 / k) * np.exp(-alpha * (k - 1)) * np.sin(k * phase)
    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out


def build_wavetable_bank(alpha: float = 0.08) -> list[np.ndarray]:
    """Pre-compute one wavetable per mipmap level.

    Called once per chord note so the per-sample render path only does
    table lookups and linear interpolation — no trig at runtime.
    """
    return [_build_table(spec[0], alpha) for spec in _MIPMAP_SPEC]


def _select_mipmap(f0: float) -> int:
    """Return the richest mipmap level that won't alias at this fundamental."""
    for i, (_, max_f0) in enumerate(_MIPMAP_SPEC):
        if f0 <= max_f0:
            return i
    return len(_MIPMAP_SPEC) - 1


def _read_table_lerp(table: np.ndarray, phase: np.ndarray) -> np.ndarray:
    """Read wavetable with linear interpolation. Phase is in [0, 1)."""
    pos = phase * TABLE_SIZE
    idx = pos.astype(np.int64)
    frac = pos - idx
    idx0 = idx % TABLE_SIZE
    idx1 = (idx + 1) % TABLE_SIZE
    return table[idx0] + frac * (table[idx1] - table[idx0])


def make_carrier(
    n: int,
    fs: int,
    f0: float,
    alpha: float = 0.08,
    detune_cents: float = 4.0,
    bank: list[np.ndarray] | None = None,
) -> np.ndarray:
    """Synthesise one carrier voice: two slightly detuned oscillators summed.

    The +/-detune_cents spread thickens the tone (unison effect) without
    audible beating at small values. Both oscillators share the same mipmap
    level since their frequencies are nearly identical.
    """
    if bank is None:
        bank = build_wavetable_bank(alpha)
    table = bank[_select_mipmap(f0)]

    detune_ratio = 2.0 ** (detune_cents / 1200.0)  # cents -> frequency ratio
    t = np.arange(n, dtype=np.float64) / fs

    # Phase is kept in [0,1) so it wraps correctly inside the table reader.
    phase_lo: np.ndarray = (f0 / detune_ratio * t) % 1.0
    phase_hi: np.ndarray = (f0 * detune_ratio * t) % 1.0
    # print("phase_hi", phase_hi)

    out = 0.5 * _read_table_lerp(table, phase_lo) + 0.5 * _read_table_lerp(
        table, phase_hi
    )
    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out


def make_chord(
    n: int, fs: int, freqs: list[float], alpha: float = 0.08, detune_cents: float = 4.0
) -> np.ndarray:
    """Mix multiple carrier voices into a chord and normalize.

    The wavetable bank is built once and shared across all voices to avoid
    redundant computation.
    # TODO: accept carrier PCM as CLI input so the chord can be driven
    #       externally (e.g. from a MIDI-controlled synth).
    """
    bank = build_wavetable_bank(alpha)
    out = np.zeros(n, dtype=np.float64)
    x_axis = np.arange(n)
    # plt.figure(3)
    for i, f0 in enumerate(freqs):
        y = make_carrier(n, fs, f0, alpha, detune_cents, bank)
        # plt.plot(x_axis,y, label=f0)
        out += y
    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out


def asymmetric_follower(
    x: np.ndarray, fs: int, attack_ms: float = 3.0, release_ms: float = 30.0
) -> np.ndarray:
    """
    Causal asymmetric envelope follower.

    Uses a fast alpha on rising edges (attack) and a slow alpha on falling
    edges (release). Input x should already be rectified (abs of band signal).

      alpha = 1 - exp(-1 / (t_ms * 1e-3 * fs))   [exact bilinear form]

    This is the same single-pole IIR as an RC lowpass, but the coefficient
    switches each sample depending on whether the signal is rising or falling.
    """
    a_att: float = 1.0 - np.exp(-1.0 / (attack_ms * 1e-3 * fs))
    a_rel: float = 1.0 - np.exp(-1.0 / (release_ms * 1e-3 * fs))

    env: np.ndarray = np.zeros(len(x), dtype=np.float64)
    state: float = 0.0

    for i, sample in enumerate(x):
        alpha: float = a_att if float(sample) > state else a_rel
        state = (1.0 - alpha) * state + alpha * float(sample)
        env[i] = state

    return env


def log_band_edges(n_bands: int, f_lo: float, f_hi: float) -> np.ndarray:
    """Return logarithmically spaced band edges.

    Log spacing mirrors the ear's roughly logarithmic frequency resolution
    (critical bands / Bark scale), giving each band perceptually equal width.
    """
    return np.geomspace(f_lo, f_hi, n_bands + 1)


def main(in_path: str, out_path: str) -> None:
    """
    Pipeline:

    1)Carrier synthesis — generates a C-major chord (C3/E3/G3) from detuned wavetable oscillators, then adds echo/chorus via delay taps

    2)Analysis filterbank — splits the input audio into 32 logarithmically-spaced bandpass bands (100 Hz → 8 kHz)

    3)Envelope following — for each band, rectifies and low-pass filters to get a slowly-moving amplitude envelope

    4)Resynthesis — multiplies each carrier band by its corresponding envelope and sums everything back together
    """

    x: np.ndarray = read_pcm_f32(in_path)
    n: int = x.size
    if n == 0:
        write_pcm_f32(out_path, x)
        return

    edges: np.ndarray = log_band_edges(N_BANDS, F_LO_HZ, F_HI_HZ)

    rng = np.random.default_rng()
    white_noise = rng.uniform(low=-1, high=1, size=n)

    # C-major chord: C3 / E3 / G3.  alpha=0.03 gives a brighter timbre which
    # survives heavy bandpass filtering without sounding too muffled.
    carrier: np.ndarray = make_chord(
        n=n, fs=FS_HZ, freqs=[130.81, 164.81, 196.00], alpha=0.05
    )

    print("x min max", np.min(x), np.max(x))

    # ---- filterbank analysis / resynthesis ----
    # TODO: pre-design all BP SOS arrays here (outside the loop) to avoid
    #       redundant filter design on every call; also enables parallelization.
    out: np.ndarray = np.zeros(n, dtype=np.float64)
    rms_inv: list[float] = []
    RMS_INV = [
        1.9469390037806138,
        1.9377564679159567,
        1.7845914685863802,
        1.6728388662084763,
        1.6002564143231317,
        1.4909021605621064,
        1.4296196380824593,
        1.3588218091103241,
        1.3031854537904453,
        1.2774967944101394,
        1.2285361281452314,
        1.1434903544703194,
        1.0703384873646056,
        1.0336841725786916,
        0.9878834974796817,
        0.9333061231313134,
        0.8897837026228016,
        0.8313561198046957,
        0.7945340475436788,
        0.7474480240195407,
        0.7041364802984527,
        0.6763374522466448,
        0.6350723351990987,
        0.61188464046863,
        0.5799163492037167,
        0.5497358372659501,
        0.5225188823362087,
        0.498827709238261,
        0.4737200838234444,
        0.44915403713929697,
        0.4290647728271138,
        0.40686268602259185,
    ]

    for i, b in tqdm(enumerate(range(N_BANDS))):
        f1: float = float(edges[b])
        f2: float = float(edges[b + 1])
        if f2 >= FS_HZ / 2:
            f2 = FS_HZ / 2 - 1.0  # clamp to Nyquist
        if f1 >= f2:
            continue

        print([f1, f2])

        # Bandpass the modulator (voice).
        # sosfilt(sos, signal) — applies the SOS filter to the signal sample-by-sample
        # in the time domain (direct-form II transposed biquad chain). It is causal:
        # each output sample depends only on current and past inputs, so it introduces
        # group delay. For offline use sosfiltfilt() would give zero phase instead.
        bp_sos = butter(BP_ORDER, [f1, f2], btype="band", fs=FS_HZ, output="sos")
        band = sosfilt(bp_sos, x)

        white_noise_band = sosfilt(bp_sos, white_noise)
        rms = np.sqrt(np.mean(white_noise_band**2))
        print("rms and inv rms", rms, 1 / rms)
        rms_inv.append(1 / rms)

        # Bandpass the carrier identically so only harmonics inside [f1,f2]
        # contribute.
        carrier_band = sosfilt(bp_sos, carrier)

        # Envelope follower: full-wave rectify then track amplitude over time.
        env: np.ndarray = asymmetric_follower(np.abs(band), FS_HZ)
        print("env avg std", np.mean(env), np.std(env))

        # Modulate carrier energy by the input envelope and accumulate.
        env_gain = 1
        gain_x = 1.0
        gain_x = (0.5 / 31) * i + 0.7
        print("gain", env_gain * gain_x * RMS_INV[i])
        out += carrier_band * np.sqrt(env) * env_gain * gain_x * RMS_INV[i]

    # Add in the white noise band.
    bp_sos: np.ndarray = butter(
        BP_ORDER, [4_000, 12_000], btype="band", fs=FS_HZ, output="sos"
    )
    band: np.ndarray = sosfilt(bp_sos, x)
    env: np.ndarray = asymmetric_follower(np.abs(band), FS_HZ)
    print("white noise avg std", np.mean(white_noise), np.std(white_noise))
    carrier_band: np.ndarray = sosfilt(bp_sos, white_noise)
    out += carrier_band * env / 2**7

    # print("pre_norm rms_inv", rms_inv)
    rms_inv = (np.array(rms_inv) / np.average(rms_inv)).tolist()
    print("post_norm rms_inv", rms_inv)

    # Final peak normalization + output gain.
    peak = np.max(np.abs(out))
    if peak > 0:
        out = out / peak

    write_pcm_f32(out_path, out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python vocoder.py input.pcm output.pcm", file=sys.stderr)
        sys.exit(1)

    main(sys.argv[1], sys.argv[2])
