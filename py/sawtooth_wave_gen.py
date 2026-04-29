from os import XATTR_SIZE_MAX

import vocoder
import vocoder2


import math
import numpy as np
import matplotlib.pyplot as plt

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

A4_MIDI = 69
A4_FREQ = 440.0

A0_FREQ = 27.5
C8_FREQ = 4186+1

def midi_to_freq(midi_note):
    return A4_FREQ * (2 ** ((midi_note - A4_MIDI) / 12))


def midi_to_note_name(midi_note):
    note = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note}{octave}"


def main():
    notes_in_range = []

    midi_start = -1
    # Piano MIDI range is 21 (A0) to 108 (C8), but we can scan a bit wider safely
    for midi in range(0, 128):
        freq = midi_to_freq(midi)
        # if 100 <= freq <= 1000:
        if A0_FREQ <= freq <= C8_FREQ:
            notes_in_range.append((midi_to_note_name(midi), round(freq, 2)))
            if midi_start == -1:
                midi_start = midi

    note_bit = 16
    total_cost = 0
    start_index = [0] 
    carriers_list = []
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
            int(discrete_period) + 1, 48000, freq, alpha=.03, detune_cents=0
        )

        upper = (1 << 15) - 1
        lower = -(1 << 15)
        x *= 2**15
        x = x.astype(int)
        x = np.clip(x, a_max = upper, a_min=lower)
        assert max(x) <= upper
        assert min(x) >= lower
        x_2comp = (x + (1 << note_bit)) % (1 << note_bit)
        carriers_list.extend(x_2comp)
        start_index.append(start_index[-1] + len(x_2comp))
        # x_axis = np.arange(len(x))

        # if (freq == 440):
        if (False):
            plt.plot(x_axis,x)
            plt.show()
            print(discrete_period)
            # print(upper,lower)
            # print(x_2comp[:2], x_2comp[-2:])
            # np.savetxt('sawtooth.mem', x_2comp, fmt = "%04x")
            # break

        print(f"{note}: , {discrete_period} period, {cost} cost")
    
    print("carriers[-1]:",carriers_list[-1],"carriers num:", len(carriers_list))
    print("start_index:", start_index[-2:], "num idx", len(start_index))
    np.savetxt('sawtooth_total.mem', carriers_list, fmt = "%04x")
    np.savetxt('sawtooth_start_idx.mem', start_index, fmt = "%04x")
    print("midi_start:", midi_start)
    print(f"{total_cost/1_000_000} total_cost")

    # for note, freq in notes_in_range:


if __name__ == "__main__":
    main()
