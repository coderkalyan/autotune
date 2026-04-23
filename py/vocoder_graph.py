"""Simple time-domain channel vocoder demo + educational visualization.

Usage:
    python vocoder_graph.py input.pcm output.pcm [--viz]
    python vocoder_graph.py input.pcm output.pcm --viz-out figure.png
    python vocoder_graph.py input.pcm output.pcm --viz --viz-start 1.0 --viz-end 2.5

Reads raw float32 PCM (mono) at FS_HZ, vocodes it against a synthesized carrier
(default: C-major chord). All filtering is in the time domain (no FFT).

Algorithm overview (per band):
    speech -> [bandpass] -> |·| -> envelope follower -> env
    carrier -> [same bandpass] -> carrier_band
    output += env * carrier_band

The visualization (optional) produces three vertically stacked plots:
speech waveform, per-band envelopes over time, and the final vocoded waveform.
"""

import argparse
import os
from typing import cast
import numpy as np
from scipy.signal import butter, sosfilt

import matplotlib

# When running headless (no X/Wayland display), ensure saving figures works.
if os.environ.get("DISPLAY", "") == "":
    matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---- configurable constants ----
FS_HZ = 48000
N_BANDS = 32  # more bands = better spectral resolution but more CPU
# F_LO_HZ = 100.0  # below ~100 Hz vocoder effect is barely audible
F_LO_HZ = 300.0  # below ~100 Hz vocoder effect is barely audible
F_HI_HZ = 8000.0  # above ~8 kHz mostly noise/sibilance; can be raised
ENV_ATTACK_MS = 5.0
ENV_RELEASE_MS = 60.0
BP_ORDER = 2  # order-2 biquad; raise to 4 for sharper band separation
OUTPUT_GAIN = 2.0

# Plotting uses a downsampled view for speed/clarity.
VIZ_MAX_SECONDS = 2.0
VIZ_MAX_SAMPLES = 6000

# Heatmap display normalization.
ENV_REF_PERCENTILE = 95.0
ENV_FLOOR_DB = -40.0

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
    for f0 in freqs:
        y = make_carrier(n, fs, f0, alpha, detune_cents, bank)
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
                        attack_ms: float = 3.0,
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


def _band_centers(edges: np.ndarray) -> np.ndarray:
    """Geometric centers for log-spaced bands (useful for labeling)."""
    f1 = edges[:-1]
    f2 = edges[1:]
    return np.sqrt(f1 * f2)


def _design_bandpass_sos(edges: np.ndarray, fs: int, order: int) -> list[np.ndarray]:
    """Design a Butterworth bandpass SOS for each band."""
    sos_list: list[np.ndarray] = []
    for b in range(len(edges) - 1):
        f1 = float(edges[b])
        f2 = float(edges[b + 1])
        nyq = fs / 2.0
        if f2 >= nyq:
            f2 = nyq - 1.0
        if f1 >= f2:
            sos_list.append(np.zeros((0, 6), dtype=np.float64))
            continue
        sos = cast(np.ndarray, butter(order, [f1, f2], btype="band", fs=fs, output="sos"))
        sos_list.append(np.asarray(sos, dtype=np.float64))
    return sos_list


def vocode(
    x: np.ndarray,
    fs: int,
    carrier: np.ndarray,
    *,
    edges: np.ndarray,
    bp_sos_list: list[np.ndarray] | None = None,
    collect_envelopes: bool = False,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Vocode x onto carrier using a multi-band filterbank.

    Returns (y, env_matrix). env_matrix is shape (n_bands, n) if collected,
    otherwise None.
    """
    x = np.asarray(x, dtype=np.float64)
    carrier = np.asarray(carrier, dtype=np.float64)
    if x.shape != carrier.shape:
        raise ValueError("x and carrier must have the same length")

    if bp_sos_list is None:
        bp_sos_list = _design_bandpass_sos(edges, fs, BP_ORDER)

    y = np.zeros_like(x)
    env_matrix = (
        np.zeros((len(bp_sos_list), len(x)), dtype=np.float64) if collect_envelopes else None
    )

    for b, bp_sos in enumerate(bp_sos_list):
        if bp_sos.size == 0:
            continue

        speech_band = sosfilt(bp_sos, x)
        carrier_band = sosfilt(bp_sos, carrier)

        env = asymmetric_follower(
            np.abs(speech_band),
            fs,
            attack_ms=ENV_ATTACK_MS,
            release_ms=ENV_RELEASE_MS,
        )
        if env_matrix is not None:
            env_matrix[b, :] = env

        y += env * carrier_band

    peak = float(np.max(np.abs(y)))
    if peak > 0:
        y = (y / peak) * OUTPUT_GAIN
    return y.astype(np.float64), env_matrix


def _slice_and_decimate_for_viz(
    x: np.ndarray,
    fs: int,
    *,
    start_s: float = 0.0,
    end_s: float | None = None,
    max_seconds: float = VIZ_MAX_SECONDS,
    max_samples: int = VIZ_MAX_SAMPLES,
) -> tuple[np.ndarray, np.ndarray, int, int, int]:
    """Return a decimated view of x over a chosen time window.

    Returns (t, x_decimated, start_idx, end_idx, stride).
    """
    n = int(len(x))
    if n == 0:
        return np.zeros(0, dtype=np.float64), x, 0, 0, 1

    start_idx = int(round(max(0.0, start_s) * fs))
    if end_s is None:
        end_idx = start_idx + int(round(max_seconds * fs))
    else:
        end_idx = int(round(max(0.0, end_s) * fs))

    start_idx = int(np.clip(start_idx, 0, n))
    end_idx = int(np.clip(end_idx, start_idx, n))

    win_n = max(0, end_idx - start_idx)
    if win_n == 0:
        return np.zeros(0, dtype=np.float64), x[0:0], start_idx, end_idx, 1

    stride = max(1, int(np.ceil(win_n / max_samples)))
    xw = x[start_idx:end_idx:stride]
    # Absolute time axis (seconds) for the selected window.
    t = (start_idx + np.arange(len(xw), dtype=np.float64) * stride) / fs
    return t, xw, start_idx, end_idx, stride


def _normalize_envelopes_for_heatmap(
    envelopes: np.ndarray,
    *,
    ref_percentile: float = ENV_REF_PERCENTILE,
    floor_db: float = ENV_FLOOR_DB,
) -> np.ndarray:
    """Convert envelopes to a log (dB) heatmap without boosting near-silence.

    Strategy (per band):
      - pick a robust reference level (e.g., 95th percentile)
      - map to a dB scale relative to that reference (log scale)
      - clamp everything below floor_db to the same dark color

    Returns dB values in [floor_db, 0]. This avoids the common pitfall of
    per-band max normalization, which can artificially amplify noise in weak
    bands.
    """
    env = np.asarray(envelopes, dtype=np.float64)
    if env.ndim != 2 or env.shape[1] == 0:
        return env

    eps = 1e-12
    ref = np.percentile(env, ref_percentile, axis=1, keepdims=True)

    # If a band is effectively silent, keep it at the floor.
    silent = ref < 1e-6
    ref = np.maximum(ref, 1e-6)

    # Relative dB: 0 dB at ref, negative below.
    rel = env / (ref + eps)
    rel_db = 20.0 * np.log10(rel + eps)
    rel_db = np.clip(rel_db, floor_db, 0.0)
    rel_db[silent[:, 0], :] = floor_db
    return rel_db


def plot_vocoder_visualization(
    *,
    t: np.ndarray,
    speech: np.ndarray,
    envelopes: np.ndarray,
    output: np.ndarray,
    band_centers_hz: np.ndarray,
) -> None:
    """Three-panel educational visualization (exactly 3 vertically stacked plots)."""
    fig, axes = plt.subplots(
        3,
        1,
        sharex=True,
        figsize=(10, 7),
        constrained_layout=True,
    )

    ax0, ax1, ax2 = axes

    ax0.plot(t, speech, lw=1.0)
    ax0.set_title("Input speech waveform (time domain)")
    ax0.set_ylabel("Amplitude")

    env_db = _normalize_envelopes_for_heatmap(envelopes)

    im = ax1.imshow(
        env_db,
        aspect="auto",
        origin="lower",
        extent=(float(t[0]), float(t[-1]), 0.0, float(env_db.shape[0])),
        interpolation="nearest",
        vmin=ENV_FLOOR_DB,
        vmax=0.0,
    )
    ax1.set_title("Per-band envelopes used to modulate carrier bands")
    ax1.set_ylabel("Band (low → high)")

    # Heatmap key (colorbar). This is a legend for the middle plot, not an extra subplot.
    cbar = fig.colorbar(im, ax=ax1, pad=0.01, fraction=0.035)
    cbar.set_label("Envelope level (dB, per-band reference)")
    cbar.set_ticks([ENV_FLOOR_DB, ENV_FLOOR_DB / 2.0, 0.0])

    # Keep labels clean: show only the lowest and highest band frequencies.
    if env_db.shape[0] == len(band_centers_hz) and env_db.shape[0] > 0:
        lo_i = 0
        hi_i = int(env_db.shape[0] - 1)
        ax1.set_yticks([lo_i + 0.5, hi_i + 0.5])
        ax1.set_yticklabels([f"{band_centers_hz[lo_i]:.0f} Hz", f"{band_centers_hz[hi_i]:.0f} Hz"])

    ax2.plot(t, output, lw=1.0)
    ax2.set_title("Output waveform: sum of (envelope × carrier band)")
    ax2.set_ylabel("Amplitude")

    # One shared x-axis label keeps the layout clean.
    fig.supxlabel("Time (s)")

    # Consistent x-limits across all three panels.
    for ax in axes:
        ax.set_xlim(float(t[0]), float(t[-1]))




def main(
    in_path: str,
    out_path: str,
    *,
    viz: bool = False,
    viz_out: str | None = None,
    viz_start: float = 0.0,
    viz_end: float | None = None,
) -> None:
    x = read_pcm_f32(in_path)
    n = int(x.size)
    if n == 0:
        write_pcm_f32(out_path, x)
        return

    if viz:
        dur_s = n / FS_HZ
        if viz_start < 0.0 or viz_start > dur_s:
            raise ValueError(f"--viz-start must be within [0, {dur_s:.3f}] seconds")
        if viz_end is not None:
            if viz_end < 0.0 or viz_end > dur_s:
                raise ValueError(f"--viz-end must be within [0, {dur_s:.3f}] seconds")
            if viz_end <= viz_start:
                raise ValueError("--viz-end must be greater than --viz-start")

    edges = log_band_edges(N_BANDS, F_LO_HZ, F_HI_HZ)
    bp_sos_list = _design_bandpass_sos(edges, FS_HZ, BP_ORDER)

    # Carrier: C-major chord (C3/E3/G3) synthesized by detuned wavetables.
    # carrier = make_chord(n=n, fs=FS_HZ, freqs=[130.81, 164.81, 196.00], alpha=0.05)
    carrier = make_chord(n=n, fs=FS_HZ, freqs=[130.81], alpha=0.05, detune_cents=0)

    y, envs = vocode(
        x,
        FS_HZ,
        carrier,
        edges=edges,
        bp_sos_list=bp_sos_list,
        collect_envelopes=viz,
    )

    write_pcm_f32(out_path, y)

    if viz and envs is not None:
        # Build a decimated view for plotting over the requested time range.
        t, xw, start_idx, end_idx, stride = _slice_and_decimate_for_viz(
            x.astype(np.float64),
            FS_HZ,
            start_s=viz_start,
            end_s=viz_end,
        )
        if t.size == 0:
            raise ValueError("Selected visualization window is empty")
        # Use the exact same indices/stride for every plotted signal so all
        # panels share the same time base.
        yw = y.astype(np.float64)[start_idx:end_idx:stride]
        envw = envs[:, start_idx:end_idx:stride]

        plot_vocoder_visualization(
            t=t,
            speech=xw,
            envelopes=envw,
            output=yw,
            band_centers_hz=_band_centers(edges),
        )

        if viz_out:
            plt.savefig(viz_out, dpi=150)
        else:
            plt.show()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Time-domain channel vocoder")
    parser.add_argument("input", help="Input raw float32 PCM (mono) at FS_HZ")
    parser.add_argument("output", help="Output raw float32 PCM (mono) at FS_HZ")
    parser.add_argument(
        "--viz",
        action="store_true",
        help="Show a 3-panel visualization (speech, envelopes, vocoded output)",
    )
    parser.add_argument(
        "--viz-out",
        default=None,
        help="Save the visualization to a PNG instead of showing it",
    )
    parser.add_argument(
        "--viz-start",
        type=float,
        default=0.0,
        help="Visualization window start time in seconds (default: 0.0)",
    )
    parser.add_argument(
        "--viz-end",
        type=float,
        default=None,
        help="Visualization window end time in seconds (default: start + VIZ_MAX_SECONDS)",
    )
    args = parser.parse_args()
    main(
        args.input,
        args.output,
        viz=bool(args.viz or args.viz_out),
        viz_out=args.viz_out,
        viz_start=float(args.viz_start),
        viz_end=(None if args.viz_end is None else float(args.viz_end)),
    )
