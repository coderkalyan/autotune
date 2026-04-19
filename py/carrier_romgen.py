"""Generate mellow organ-style carrier ROMs for the vocoder synth.

Mirrors sawtooth_wave_gen.py's structure (same notes, same per-note period
length, same int16 two's-complement hex layout) but replaces the sawtooth
carrier with a drawbar-organ voice from organ.py.

Outputs:
    carriers.mem          - concatenated int16 samples, one per line
    carrier_indices.mem   - per-note start indices into carriers.mem
"""

import numpy as np

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

A4_MIDI = 69
A4_FREQ = 440.0
F_LO = 100.0
F_HI = 1000.0

FS = 48000
NOTE_BIT = 16

# Full Maj9 voicing from organ.py. Every ratio is a multiple of 1/8 so
# the summed carrier is exactly periodic over PERIOD_MULT=8 periods of
# the root f0 -> ROM loops cleanly. Pure sines (no drawbar stack, no
# detune) so every component is a true harmonic of the ROM fundamental.
# Maj3 triad tones (root 1.0, major 3rd 1.25, 5th 1.5) heavily boosted to
# dominate the voicing; the remaining Maj9 chord tones stay at their
# organ.py amps as colouring.
CHORD_RATIOS = [0.125, 0.25, 0.375, 0.5, 0.75, 1.0, 1.125, 1.25, 1.5, 2.0]
CHORD_AMPS   = [0.6,   0.8,  0.5,   0.9, 0.6,  2.5, 0.4,   2.0, 2.2, 0.35]
PERIOD_MULT  = 8

# Sawtooth (at f0) overlaid on the organ chord. Sawtooth is a sum of
# 1/n * sin(2π n f0 t) — every harmonic is an integer multiple of f0, so
# it stays periodic over the same ROM length.
SAW_AMP = 0.8  # relative to the normalized organ chord (pre-final-normalize)


def midi_to_freq(midi_note):
    return A4_FREQ * (2 ** ((midi_note - A4_MIDI) / 12))


def midi_to_note_name(midi_note):
    note = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note}{octave}"


def make_sawtooth(n, fs, f0):
    """Band-limited sawtooth at f0 via additive synthesis."""
    t = np.arange(n) / fs
    sig = np.zeros_like(t)
    n_max = int((fs / 2) / f0)  # highest integer harmonic below Nyquist
    for k in range(1, n_max + 1):
        sig += (1.0 / k) * np.sin(2 * np.pi * (k * f0) * t)
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig / peak
    return sig


def make_chord_carrier(n, fs, f0):
    """n-sample pure-sine Maj9 chord carrier rooted at f0, with a low-level
    sawtooth overlay at f0 for added harmonic bite."""
    t = np.arange(n) / fs
    sig = np.zeros_like(t)
    for r, a in zip(CHORD_RATIOS, CHORD_AMPS):
        sig += a * np.sin(2 * np.pi * (f0 * r) * t)
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig / peak  # organ chord normalized to unit peak
    sig += SAW_AMP * make_sawtooth(n, fs, f0)
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig / peak  # final normalize so the sample fits int16
    return sig


def main():
    notes_in_range = []
    midi_start = -1
    for midi in range(0, 128):
        freq = midi_to_freq(midi)
        if F_LO <= freq <= F_HI:
            notes_in_range.append((midi_to_note_name(midi), freq))
            if midi_start == -1:
                midi_start = midi

    total_cost = 0
    start_index = [0]
    carriers_list = []
    upper = (1 << 15) - 1
    lower = -(1 << 15)

    for note, freq in notes_in_range:
        discrete_period = FS / freq
        # Round to the nearest whole-sample approximation of PERIOD_MULT
        # periods so every chord harmonic (all multiples of f0/PERIOD_MULT)
        # completes an integer number of cycles over the ROM.
        n = int(round(PERIOD_MULT * discrete_period))
        cost = n * NOTE_BIT
        total_cost += cost

        x = make_chord_carrier(n, FS, freq)
        x = x * (2**15)
        x = x.astype(int)
        x = np.clip(x, a_max=upper, a_min=lower)
        assert x.max() <= upper
        assert x.min() >= lower
        x_2comp = (x + (1 << NOTE_BIT)) % (1 << NOTE_BIT)
        carriers_list.extend(x_2comp)
        start_index.append(start_index[-1] + len(x_2comp))
        print(f"{note}: {discrete_period} period, {cost} cost")

    print("carriers[-1]:", carriers_list[-1], "carriers num:", len(carriers_list))
    print("start_index:", start_index[-2:], "num idx", len(start_index))
    np.savetxt("carriers.mem", carriers_list, fmt="%04x")
    # %05x (20 bits) — start indices now overflow 16-bit hex at PERIOD_MULT=8.
    np.savetxt("carrier_indices.mem", start_index, fmt="%05x")
    print("midi_start:", midi_start)
    print(f"{total_cost / 1_000_000} total_cost")


if __name__ == "__main__":
    main()
