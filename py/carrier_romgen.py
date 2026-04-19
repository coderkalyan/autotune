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

# Chord on a 1/2 grid — root + 5th + octave. The 5th (1.5 = 3/2) is the
# one tone that needs PERIOD_MULT>=2 to be a pure harmonic of the ROM
# fundamental; root and octave alone would fit in PERIOD_MULT=1.
CHORD_RATIOS = [1.0, 1.5, 2.0]
CHORD_AMPS   = [1.0, 0.6, 0.35]
PERIOD_MULT  = 2


def midi_to_freq(midi_note):
    return A4_FREQ * (2 ** ((midi_note - A4_MIDI) / 12))


def midi_to_note_name(midi_note):
    note = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note}{octave}"


def make_chord_carrier(n, fs, f0):
    """n-sample pure-sine Maj9 chord carrier rooted at f0."""
    t = np.arange(n) / fs
    sig = np.zeros_like(t)
    for r, a in zip(CHORD_RATIOS, CHORD_AMPS):
        sig += a * np.sin(2 * np.pi * (f0 * r) * t)
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig / peak
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
    np.savetxt("carrier_indices.mem", start_index, fmt="%04x")
    print("midi_start:", midi_start)
    print(f"{total_cost / 1_000_000} total_cost")


if __name__ == "__main__":
    main()
