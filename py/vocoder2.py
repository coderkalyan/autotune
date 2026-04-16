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
# ---- configurable constants ----
FS_HZ = 48000
N_BANDS = 32  # more bands = better spectral resolution but more CPU
# F_LO_HZ = 100.0  # below ~100 Hz vocoder effect is barely audible
F_LO_HZ = 300.0  # below ~100 Hz vocoder effect is barely audible
F_HI_HZ = 8000.0  # above ~8 kHz mostly noise/sibilance; can be raised
ENV_CUTOFF_HZ = 30.0  # envelope follower LPF cutoff; lower = smoother but slower attack
# TODO: replace with asymmetric follower (fast attack ~3 ms, slow release ~100 ms)
BP_ORDER = 2  # order-2 biquad; raise to 4 for sharper band separation
# TODO: consider constant-Q (gammatone) filterbank for better perceptual alignment
ENV_ORDER = 2
OUTPUT_GAIN = 2.0

# Delay taps create a chorus/reverb spread on the carrier *before* vocoding,
# so the vocodered result sounds wider and less dry.
FX_TAPS = [(0.017, 0.45), (0.029, 0.35), (0.053, 0.25), (0.091, 0.18)]
FX_WET = 0.35

# ---- wavetable constants ----
TABLE_SIZE = 4096  # one full oscillator cycle; larger = less interpolation error

# Mipmap levels limit harmonic count per pitch range to prevent aliasing.
# Each entry is (max_harmonics, max_f0_hz_this_level_is_safe_for).
# "Safe" means: max_harmonics * f0 < fs/2.
_MIPMAP_SPEC = [
    (96, 250.0),  # level 0: richest, only for low fundamentals
    (48, 500.0),
    (24, 1000.0),
    (12, 2000.0),  # level 3: sparsest, fallback for high pitches
]




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
    phase_lo:np.ndarray = (f0 / detune_ratio * t) % 1.0
    phase_hi:np.ndarray = (f0 * detune_ratio * t) % 1.0
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
    for i,f0 in enumerate(freqs):
        y = make_carrier(n, fs, f0, alpha, detune_cents, bank)
        # plt.plot(x_axis,y, label=f0)
        out += y
    peak = np.max(np.abs(out))
    if peak > 0:
        out /= peak
    return out


def causal_rms(x: np.ndarray, fs: int, window_ms: float = 50.0) -> np.ndarray:
    """
    Causal running RMS via a 2-pole IIR smoother on x^2.
 
    Two cascaded single-pole sections are used instead of one:
      - pole 1 smooths x^2, producing a running mean-square estimate
      - pole 2 smooths that estimate again, steepening the rolloff to
        -40 dB/decade so double-frequency ripple (which lives at 2*f_band
        in the squared signal) is more strongly suppressed on low bands
        where 2*f_band is close to the smoothing cutoff.
 
    Both poles share the same alpha (same time constant). The impulse
    response shape changes from pure exponential (1 pole) to n*(1-a)^n
    (2 poles) — a soft onset that ramps up briefly before decaying, which
    means the estimate reacts slightly more gradually to sudden onsets but
    has a cleaner steady-state estimate.
 
    window_ms is the RC time constant for each pole. 50 ms balances
    stability against responsiveness for vocoder band gain tracking.
    """
    alpha: float = 1.0 - np.exp(-1.0 / (window_ms * 1e-3 * fs))
 
    mean_sq: np.ndarray = np.zeros(len(x), dtype=np.float64)
    state1: float = 0.0   # first pole state  — smooths x^2
    state2: float = 0.0   # second pole state — smooths state1
 
    for i, sample in enumerate(x):
        sq: float = float(sample) ** 2
        state1 = (1.0 - alpha) * state1 + alpha * sq       # pole 1
        state2 = (1.0 - alpha) * state2 + alpha * state1   # pole 2
        mean_sq[i] = state2
 
    return np.sqrt(mean_sq)


def asymmetric_follower(x: np.ndarray,
                        fs: int,
                        attack_ms: float = 2.0,
                        release_ms: float = 30.0) -> np.ndarray:
    """
    Causal asymmetric envelope follower.
 
    Uses a fast alpha on rising edges (attack) and a slow alpha on falling
    edges (release). Input x should already be rectified (abs of band signal).
 
      alpha = 1 - exp(-1 / (t_ms * 1e-3 * fs))   [exact bilinear form]
 
    This is the same single-pole IIR as an RC lowpass, but the coefficient
    switches each sample depending on whether the signal is rising or falling.
    """
    a_att: float = 1.0 - np.exp(-1.0 / (attack_ms  * 1e-3 * fs))
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

    # butter(order, cutoff, btype, fs) — designs a Butterworth IIR filter.
    # A Butterworth filter has a maximally flat passband (no ripple) and rolls
    # off smoothly outside it. order controls roll-off steepness: order 2 means
    # -40 dB/decade. output="sos" returns second-order sections — a numerically
    # stable cascade of biquad stages, safer than raw transfer-function
    # coefficients for higher-order filters.
    #
    # Single shared envelope LPF design reused for every band.
    # TODO: replace with asymmetric RC follower for snappier transients.
    env_sos: np.ndarray = butter(
        ENV_ORDER, ENV_CUTOFF_HZ, btype="low", fs=FS_HZ, output="sos"
    )

    # C-major chord: C3 / E3 / G3.  alpha=0.03 gives a brighter timbre which
    # survives heavy bandpass filtering without sounding too muffled.
    carrier: np.ndarray = make_chord(
        n=n, fs=FS_HZ, freqs=[130.81, 164.81, 196.00], alpha=0.03
    )
    
    # Comb-filter chorus/reverb on the carrier via delay taps.
    # Applied before vocoding so the spatial width is baked into every band.
    # wet: np.ndarray = np.zeros(n, dtype=np.float64)
    # for delay_s, gain in FX_TAPS:
    #     d: int = int(delay_s * FS_HZ)
    #     if 0 < d < n:
    #         wet[d:] += gain * carrier[:-d]
    # carrier = carrier + FX_WET * wet

    # ---- filterbank analysis / resynthesis ----
    # TODO: pre-design all BP SOS arrays here (outside the loop) to avoid
    #       redundant filter design on every call; also enables parallelization.
    out: np.ndarray = np.zeros(n, dtype=np.float64)
    rms_inv:list[float] = []
    RMS_INV = [1.0076614202676992, 0.9460489898021014, 0.8668215847220266, 0.8235411415894907, 0.8110827996524813, 0.7654611314083096, 0.7491222989739165, 0.6909487799431292, 0.6619996987762434, 0.6138620440581962, 0.5952359269385344, 0.5795490583028692, 0.540725297823205, 0.5104493499638932, 0.48358494826079707, 0.4610298837234944, 0.43212920269497995, 0.4166317055359978, 0.39564795569477507, 0.3759444465944871, 0.35433528153792926, 0.33858061230695213, 0.3236712700162232, 0.30503175526769044, 0.29184839155365466, 0.2753869660814464, 0.26012503462577274, 0.24900865742453943, 0.23557655098045793, 0.22423527150364475, 0.2139284747903463, 0.20079406918471623]

    # for b in range(N_BANDS):
    for i, b in enumerate(tqdm(range(N_BANDS))):
        f1: float = float(edges[b])
        f2: float = float(edges[b + 1])
        if f2 >= FS_HZ / 2:
            f2 = FS_HZ / 2 - 1.0  # clamp to Nyquist
        if f1 >= f2:
            continue

        print([f1,f2])
        # continue
        
        

        # 1. Bandpass the modulator (voice) to isolate this frequency slice.
        #    btype="band" makes butter() design a bandpass filter with
        #    cutoff edges at [f1, f2] Hz instead of a single corner frequency.
        bp_sos: np.ndarray = butter(
            BP_ORDER, [f1, f2], btype="band", fs=FS_HZ, output="sos"
        )

        # sosfilt(sos, signal) — applies the SOS filter to the signal sample-by-sample
        # in the time domain (direct-form II transposed biquad chain). It is causal:
        # each output sample depends only on current and past inputs, so it introduces
        # group delay. For offline use sosfiltfilt() would give zero phase instead.
        band: np.ndarray = sosfilt(bp_sos, x)
        
        white_noise_band: np.ndarray = sosfilt(bp_sos, white_noise)
        rms = np.sqrt(np.mean(white_noise_band**2))
        print("rms and inv rms",rms,1/rms)
        rms_inv.append(1/rms)
        

        # 2(old). Envelope follower: full-wave rectify then smooth with LPF.
        #    The *128 scalar compensates for energy loss from narrow bandpassing;
        #    it is a magic number — per-band RMS normalization would be more robust.
        #    TODO: use sosfiltfilt (zero-phase) for offline use to remove group-delay
        #          smear that makes transients sound "swimmy".
        # env: np.ndarray = sosfilt(env_sos, np.abs(band)) * 128


        # 3. Bandpass the carrier identically so only harmonics inside [f1,f2]
        #    contribute — this is the key resynthesis step.
        carrier_band: np.ndarray = sosfilt(bp_sos, carrier)

        # 2. Envelope follower: full-wave rectify then track amplitude over time.
        #
        #    CURRENT (simple LPF):
        #        env = sosfilt(env_sos, np.abs(band)) * 128
        #    Single pole at 30 Hz — same speed on attack and release.
        #    The *128 is a magic scalar; too loud for some bands, too quiet for others.
        #
        #    IMPROVED (asymmetric follower + per-band causal RMS gain) — copy-paste to replace:
        #    -------------------------------------------------------------------------
        #        carrier_rms: np.ndarray = causal_rms(carrier_band, FS_HZ) + 1e-9
        #        band_rms:    np.ndarray = causal_rms(band,          FS_HZ) + 1e-9
        #        gain:        np.ndarray = band_rms / carrier_rms   # time-varying, shape (n,)
        #        env: np.ndarray = asymmetric_follower(np.abs(band), FS_HZ) * gain
        #    -------------------------------------------------------------------------
        #    causal_rms() uses a 2-pole IIR on x^2 — the second pole adds -40 dB/decade
        #    rolloff which suppresses double-frequency ripple on low bands (e.g. a 100 Hz
        #    band produces x^2 content at 200 Hz; one pole barely attenuates it, two poles
        #    largely remove it). gain is now an array not a scalar so it adjusts over time
        #    as band energy shifts, replacing the fixed *128 magic number entirely.
        # carrier_rms: np.ndarray = causal_rms(carrier_band, FS_HZ) + 1e-9
        # band_rms:    np.ndarray = causal_rms(band,          FS_HZ) + 1e-9
        # env_gain:    np.ndarray = band_rms / carrier_rms   # time-varying, shape (n,)
        env_gain = 128
        gain_x = (.5/31)*i + .7
        # gain_x = 1
        env: np.ndarray = asymmetric_follower(np.abs(band), FS_HZ)
        print("env avg std",np.mean(env),np.std(env))

        # 4. Modulate carrier energy by the input envelope and accumulate.
        # out += carrier_band * np.sqrt(env) * env_gain * gain_x
        print("gain", env_gain * gain_x * RMS_INV[i])
        out += carrier_band * np.sqrt(env) * env_gain * gain_x * RMS_INV[i]
    bp_sos: np.ndarray = butter(
            BP_ORDER, [5_000, 10_000], btype="band", fs=FS_HZ, output="sos"
        )
    band: np.ndarray = sosfilt(bp_sos, x)
    env: np.ndarray = asymmetric_follower(np.abs(band), FS_HZ)
    print("white noise avg std",np.mean(white_noise),np.std(white_noise))
    carrier_band: np.ndarray = sosfilt(bp_sos, white_noise)
    out += carrier_band * np.sqrt(env)
    
    # print("pre_noram rms_inv", rms_inv)
    rms_inv = (np.array(rms_inv)/np.average(rms_inv)/2).tolist()
    print("post_noram rms_inv", rms_inv)

    # Final peak normalization + output gain.
    peak = np.max(np.abs(out))
    if peak > 0:
        out = out / peak * OUTPUT_GAIN

    write_pcm_f32(out_path, out)


if __name__ == "__main__":
    # x = build_wavetable_bank()
    # print(len(x))
    # print(len(x[0]))
    # print(x[0])
    # ans = 0
    # for i in x:
    #     ans += len(i)
    
    # plt.figure(1)
    # x_axis = np.arange(len(x[0]))
    # print(x_axis)
    # for i in range(len(x)):
    #     plt.plot(x_axis,x[i],label=i)
    
    # print(ans)
    # edges: np.ndarray = log_band_edges(N_BANDS, F_LO_HZ, F_HI_HZ)
    # n = 440
    # x_axis = np.arange(n)
    # # C-major chord: C3 / E3 / G3.  alpha=0.03 gives a brighter timbre which
    # # survives heavy bandpass filtering without sounding too muffled.
    # carrier: np.ndarray = make_chord(
    #     n=n, fs=FS_HZ, freqs=[130.81, 164.81, 196.00], alpha=0.00
    #     # n=n, fs=FS_HZ, freqs=[440], alpha=0.00
    # )

    # plt.figure(2)
    # plt.plot(x_axis, carrier)
    
    # plt.legend()
    # plt.show()

    # # Comb-filter chorus/reverb on the carrier via delay taps.
    # # Applied before vocoding so the spatial width is baked into every band.
    # wet: np.ndarray = np.zeros(n, dtype=np.float64)
    # for delay_s, gain in FX_TAPS:
    #     d: int = int(delay_s * FS_HZ)
    #     if 0 < d < n:
    #         wet[d:] += gain * carrier[:-d]
    # carrier = carrier + FX_WET * wet
    # for b in range(N_BANDS):
    #     f1: float = float(edges[b])
    #     f2: float = float(edges[b + 1])
    #     if f2 >= FS_HZ / 2:
    #         f2 = FS_HZ / 2 - 1.0  # clamp to Nyquist
    #     if f1 >= f2:
    #         continue
    if len(sys.argv) != 3:
        print("usage: python vocoder.py input.pcm output.pcm", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
