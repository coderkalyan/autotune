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
A0_FREQ = 27.5
C8_FREQ = 4186 + 1

FS = 48000
NOTE_BIT = 16

# Mellow drawbar organ voicing (from organ.py)
DRAWBARS = [8, 5, 8, 4, 6, 5, 3, 5, 4]
RATIOS = [0.5, 1.5, 1, 2, 3, 4, 5, 6, 8]
# DETUNES_CENTS = [-7, -3, 0, 3, 7]
DETUNES_CENTS = [0]


def midi_to_freq(midi_note):
    return A4_FREQ * (2 ** ((midi_note - A4_MIDI) / 12))


def midi_to_note_name(midi_note):
    note = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note}{octave}"


def make_organ_carrier(n, fs, f0):
    """n-sample mellow organ carrier at fundamental f0."""
    t = np.arange(n) / fs
    sig = np.zeros_like(t)
    for dc in DETUNES_CENTS:
        fd = f0 * (2 ** (dc / 1200))
        voice = sum(
            (d / 8) * np.sin(2 * np.pi * fd * r * t) for d, r in zip(DRAWBARS, RATIOS)
        )
        sig += voice / len(DETUNES_CENTS)
    peak = np.max(np.abs(sig))
    if peak > 0:
        sig = sig / peak
    return sig


def main():
    notes_in_range = []
    midi_start = -1
    for midi in range(0, 128):
        freq = midi_to_freq(midi)
        if A0_FREQ <= freq <= C8_FREQ:
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
        n = int(discrete_period) + 1
        cost = discrete_period * NOTE_BIT
        total_cost += cost

        x = make_organ_carrier(n, FS, freq)
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
