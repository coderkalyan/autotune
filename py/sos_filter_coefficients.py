from os import XATTR_SIZE_MAX

import vocoder

# from vocoder2 import *
import vocoder2
from scipy.signal import butter, sosfilt

import math
import numpy as np
import matplotlib.pyplot as plt


Q11_16_FRAC_BITS = 16
Q11_16_WIDTH_BITS = 27


def _round_half_away_from_zero(x: float) -> int:
    if x >= 0.0:
        return int(math.floor(x + 0.5))
    return int(math.ceil(x - 0.5))


def q11_16_saturate(scaled_int: int) -> int:
    min_int = -(1 << (Q11_16_WIDTH_BITS - 1))
    max_int = (1 << (Q11_16_WIDTH_BITS - 1)) - 1
    return max(min(scaled_int, max_int), min_int)


def float_to_q11_16_bits(x: float) -> int:
    """Quantize a float into Q11.16 and return the 27-bit two's-complement bit pattern."""
    scaled = _round_half_away_from_zero(x * (1 << Q11_16_FRAC_BITS))
    saturated = q11_16_saturate(scaled)
    mask = (1 << Q11_16_WIDTH_BITS) - 1
    return int(saturated) & mask


def q11_16_bits_to_signed(bits: int) -> int:
    bits &= (1 << Q11_16_WIDTH_BITS) - 1
    sign_bit = 1 << (Q11_16_WIDTH_BITS - 1)
    if bits & sign_bit:
        return bits - (1 << Q11_16_WIDTH_BITS)
    return bits


def q11_16_bits_to_float(bits: int) -> float:
    return float(q11_16_bits_to_signed(bits)) / float(1 << Q11_16_FRAC_BITS)


def q11_16_bits_to_sv_literal(bits: int) -> str:
    digits = (Q11_16_WIDTH_BITS + 3) // 4
    bits &= (1 << Q11_16_WIDTH_BITS) - 1
    return f"{Q11_16_WIDTH_BITS}'sh{bits:0{digits}X}"

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

A4_MIDI = 69
A4_FREQ = 440.0


def midi_to_freq(midi_note):
    return A4_FREQ * (2 ** ((midi_note - A4_MIDI) / 12))


def midi_to_note_name(midi_note):
    note = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note}{octave}"

FS_HZ = 48000

def main():

    edges: np.ndarray = vocoder2.log_band_edges(
        vocoder.N_BANDS,
        vocoder.F_LO_HZ,
        vocoder.F_HI_HZ*2,
    )

    for b in range(vocoder.N_BANDS):
        f1: float = float(edges[b])
        f2: float = float(edges[b + 1])
        if f2 >= FS_HZ / 2:
            f2 = FS_HZ / 2 - 1.0  # clamp to Nyquist
        if f1 >= f2:
            continue
        bp_sos = butter(2, [f1, f2], btype="band", fs=48000, output="sos")

        # Section 1 — your w[n] equation
        b0, b1, b2 = bp_sos[0, 0], bp_sos[0, 1], bp_sos[0, 2]
        a1, a2 = bp_sos[0, 4], bp_sos[0, 5]  # bp_sos[0, 3] is always 1.0

        # Section 2 — your y[n] equation
        c0, c1, c2 = bp_sos[1, 0], bp_sos[1, 1], bp_sos[1, 2]
        d1, d2 = bp_sos[1, 4], bp_sos[1, 5]
        assert((b0-b2) <= 1e-7)
        assert((c0-c2) <= 1e-7)

        coeffs = {
            "b0": float(b0),
            "b1": float(b1),
            "b2": float(b2),
            "a1": float(a1),
            "a2": float(a2),
            # "c0": float(c0),
            # "c1": float(c1),
            # "c2": float(c2),
            # "d1": float(d1),
            # "d2": float(d2),
        }

        # fixed_bits = {name: float_to_q11_16_bits(val) for name, val in coeffs.items()}
        fixed_bits = {name: val for name, val in coeffs.items()}

        # One line per band, easy to paste into SV.
        parts = [
            f"band={b:02d}",
            f"f1={f1:9.2f}",
            f"f2={f2:9.2f}",
        ]
        for name in coeffs.keys():
            # parts.append(f"{name}={q11_16_bits_to_sv_literal(fixed_bits[name])}")
            parts.append(f"{name}={fixed_bits[name]}")
        print("  ".join(parts))

        # Optional sanity: show reconstruction error if you want to spot quantization/clipping.
        # for name in ("b0", "b1", "b2", "a1", "a2", "c0", "c1", "c2", "d1", "d2"):
        #     recon = q11_16_bits_to_float(fixed_bits[name])
        #     err = recon - coeffs[name]
        #     print(f"  {name}: float={coeffs[name]: .8e}  recon={recon: .8e}  err={err: .3e}")
        # break) < 1e-7)) < 1e-7)) < 1e-7)) < 1e-7)) < 1e-7)) < 1e-7)) < 1e-7)) < 1e-7)

        # print(f"{note}: , {discrete_period} period, {cost} cost")

    # print(f"{total_cost/1_000_000} total_cost")

    # for note, freq in notes_in_range:


if __name__ == "__main__":
    main()
