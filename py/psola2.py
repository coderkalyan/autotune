# PSOLA: Process for Modifying Digital Speech Signals
# Simplified implementation that resamples pitch periods and overlap-adds them.

import math
import numpy as np
import matplotlib.pyplot as plt

def plot_signals(signal1, signal2, label1="Signal 1", label2="Signal 2", num_samples=None):
    signal1 = np.array(signal1)
    signal2 = np.array(signal2)

    if num_samples is not None:
        signal1 = signal1[:num_samples]
        signal2 = signal2[:num_samples]

    n1 = np.arange(len(signal1))
    n2 = np.arange(len(signal2))

    fig, ax = plt.subplots(2, 1, figsize=(10,6))

    ax[0].stem(n1, signal1)
    ax[0].set_title(label1)
    ax[0].set_xlabel("Sample Index")
    ax[0].set_ylabel("Amplitude")
    ax[0].grid(True)

    ax[1].stem(n2, signal2)
    ax[1].set_title(label2)
    ax[1].set_xlabel("Sample Index")
    ax[1].set_ylabel("Amplitude")
    ax[1].grid(True)

    plt.tight_layout()
    plt.show()


import math

def centered_hann_window(signal_length, center, radius):
    """
    Create a Hann window embedded in a full-length array.

    signal_length : total length of the output window array
    center        : sample index where the window is centered
    radius        : number of samples on each side of center

    Returns:
        A list of length signal_length, with a Hann window centered
        at 'center' and zeros elsewhere.
    """
    window = [0.0] * signal_length

    start = center - radius
    end = center + radius
    N = 2 * radius + 1

    if N <= 1:
        if 0 <= center < signal_length:
            window[center] = 1.0
        return window

    for i in range(N):
        idx = start + i
        if 0 <= idx < signal_length:
            w = 0.5 * (1 - math.cos(2 * math.pi * i / (N - 1)))
            window[idx] = w

    return window

def apply_hann_window(signal, center, radius):
    """
    signal : signal (or subset of signal)

    Applies a centered Hann window to the signal.
    """

    N = len(signal)

    # create Hann window centered at the desired index
    window = centered_hann_window(N, center, radius)

    windowed = []
    for i in range(N):
        windowed.append(signal[i] * window[i])

    return windowed

def psola(signal, pitch_marks, pitch_factor):
    """
    signal        : list or numpy array of audio samples
    pitch_marks   : list of sample indices marking the start of each pitch period
    pitch_factor  : desired change in pitch (e.g., 1.2 raises pitch)
    """
    n = len(signal)
    output_length = int(n / pitch_factor + 1)
    output = [0.0] * output_length

    syn_pos = pitch_marks[0] if pitch_marks else 0

    # Process each pitch period
    for i in range(len(pitch_marks) - 1):
        m = pitch_marks[i]
        next_m = pitch_marks[i + 1]
        period = next_m - m

        # Window Parameters 
        win_radius = period
        win_len = 2 * win_radius

        # Extract window around the marker and apply hanning window
        start = max(0, m - win_radius)
        end = min(n, m + win_radius)   # end is exclusive
        win = signal[start:end]
        if m - win_radius < 0:
            win_hanned = apply_hann_window(win, m, period)
        else: 
            win_hanned = apply_hann_window(win, 240, period)

        window = centered_hann_window(len(win), m, period)

        # if i == 0:
        #     plot_signals(signal, win, "Original Signal", "win", 1000)
        #     plot_signals(signal, window, "Original Signal", "win", 1000)
        #     plot_signals(signal, win_hanned, "Original Signal", "win_hanned", 1000)
        

        # Calculate new Pitch mark and overlay and add window
        out_start = max(0,int(syn_pos - len(win_hanned) // 2))
        print(out_start)
        for j, val in enumerate(win_hanned):
            if 0 <= out_start + j < output_length:
                output[j + out_start] += val

        if i == 0:
            plot_signals(signal, output, "Original Signal", "Output", 1000)
            break

        new_period = max(1, int(period / pitch_factor))
        syn_pos += new_period

        if syn_pos >= n:
            break

        # # Resample window to new period length (nearest neighbor)
        # win_resampled = []
        # for k in range(new_period):
        #     idx = int(k * len(win_hanned) / new_period)
        #     win_resampled.append(win_hanned[idx])

        # # Overlap-add the resampled window into the output
        # out_start = int(m / pitch_factor)  # start position in output
        # for j, val in enumerate(win_resampled):
        #     if out_start + j < output_length:
        #         output[out_start + j] += val

    return output

# Example usage (students can replace with real audio data)
if __name__ == "__main__":
    # Dummy signal: a simple sinusoid
    t = np.linspace(0, 1, 48000)
    signal = np.sin(2 * math.pi * 200 * t).tolist()
    # Dummy pitch marks: every peak ()
    pitch_marks = list(range(60, len(signal), 240))

    # Increase pitch by 1.5x
    output = psola(signal, pitch_marks, 0.75)
    # print(len(output))