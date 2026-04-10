from os import XATTR_SIZE_MAX

import vocoder
import vocoder2


import math
import numpy as np
import matplotlib.pyplot as plt

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

A4_MIDI = 69
A4_FREQ = 440.0


def midi_to_freq(midi_note):
    return A4_FREQ * (2 ** ((midi_note - A4_MIDI) / 12))


def midi_to_note_name(midi_note):
    note = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note}{octave}"


def main():
    notes_in_range = []

    # Piano MIDI range is 21 (A0) to 108 (C8), but we can scan a bit wider safely
    for midi in range(0, 128):
        freq = midi_to_freq(midi)
        if 100 <= freq <= 1000:
            notes_in_range.append((midi_to_note_name(midi), round(freq, 2)))

    note_bit = 16
    total_cost = 0
    for i, (note, freq) in enumerate(notes_in_range):
        # print(f"{note}: {freq} Hz, {48000/freq} period")
        discrete_period = 48000 / freq
        cost = discrete_period * note_bit
        total_cost += cost
        # n: int, fs: int, freqs: list[float], alpha: float = 0.08, detune_cents: float = 4.0
        # x = vocoder2.make_carrier(
        #     int(discrete_period) + 1, 48000, freq, alpha=0, detune_cents=0
        # )
        x = vocoder.make_carrier(
            int(discrete_period) + 1, 48000, freq, alpha=0, detune_cents=5
        )

        upper = (1 << 15) - 1
        lower = -(1 << 15)
        x *= 2**15
        x = x.astype(int)
        x = np.clip(x, a_max = upper, a_min=lower)
        assert max(x) <= upper
        assert min(x) >= lower
        x_2comp = (x + (1 << note_bit)) % (1 << note_bit)
        x_axis = np.arange(len(x))

        if (freq == 440):
            plt.plot(x_axis,x)
            plt.show()
            print(discrete_period)
            # print(upper,lower)
            # print(x_2comp[:2], x_2comp[-2:])
            # np.savetxt('sawtooth.mem', x_2comp, fmt = "%04x")
            # break

        print(f"{note}: , {discrete_period} period, {cost} cost")
    
    print(f"{total_cost/1_000_000} total_cost")

    # for note, freq in notes_in_range:


if __name__ == "__main__":
    main()
