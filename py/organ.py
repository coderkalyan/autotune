import numpy as np
import matplotlib.pyplot as plt

# Params
fs = 48000
dur = 10
f0 = 440

# Drawbars: dip the mids, keep lows strong, moderate top — less saw-like
drawbars = [8, 5, 8, 4, 6, 5, 3, 5, 4]  # 16' 5⅓' 8' 4' 2⅔' 2' 1⅗' 1⅓' 1'
# drawbars = [8, 6, 8, 6, 8, 8, 4, 6, 6]  # 16' 5⅓' 8' 4' 2⅔' 2' 1⅗' 1⅓' 1'
ratios = [0.5, 1.5, 1, 2, 3, 4, 5, 6, 8]

# Fuller chord: sub-octave, octave, fifth, octave+root, just 3rd, 5th, octave up
# Using just intonation (1.25 not 1.26) for more fusion
# chord = [0.25, 0.5, 1, 1.26, 1.5, 2.0, 4.0]
# amps  = [0.7, 0.7, 1, 0.3, 0.7, 0.8, 0.5]
chord = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
amps  = [0.8, 0.9, 0.5, 1.0, 0.6, 0.7, 0.5, 0.25]

freqs = [f0 * ratio for ratio in chord]

# Synth (additive)
t = np.arange(int(fs * dur)) / fs
sig = np.zeros_like(t)

for f, amp in zip(freqs, amps):
    base = sum((d / 8) * np.sin(2 * np.pi * f * r * t) for d, r in zip(drawbars, ratios))
    upper = sum((d / 8) * np.sin(2 * np.pi * f * (2 ** (5 / 1200)) * r * t) for d, r in zip(drawbars, ratios))
    lower = sum((d / 8) * np.sin(2 * np.pi * f * (2 ** (-5 / 1200)) * r * t) for d, r in zip(drawbars, ratios))
    sig += (base + upper + lower) * amp

# echo
FX_TAPS = [(0.017, 0.45), (0.029, 0.35), (0.053, 0.25), (0.091, 0.18)]
FX_WET = 0.35
wet = np.zeros_like(t, dtype=np.float64)
for delay_s, gain in FX_TAPS:
    d = int(delay_s * fs)
    wet[d:] += gain * sig[:-d]
sig = sig + FX_WET * wet

sig = sig / np.max(np.abs(sig))

# sawtooth
# t = np.arange(int(fs * dur)) / fs
# sig = np.zeros_like(t)
# for f, amp in zip(freqs, amps):
#     for detune in [1.0, 2 ** (5/1200), 2 ** (-5/1200)]:
#         fd = f * detune
#         n_max = int((fs / 2) / fd)  # highest harmonic below Nyquist
#         for n in range(1, n_max + 1):
#             sig += (1 / n) * np.sin(2 * np.pi * fd * n * t) * amp
# sig = sig / np.max(np.abs(sig))

# Write s16be raw PCM
pcm = (sig * 32767).astype('>i2')
pcm.tofile('carrier.pcm')

# Plot 1 period
period = int(fs / f0)
fig, ax = plt.subplots(2, 1, figsize=(10, 6))
ax[0].plot(t[:period] * 1000, sig[:period])
ax[0].set_xlabel('ms'); ax[0].set_ylabel('amp'); ax[0].set_title('1 period')

# Plot FFT
N = 1 << 15
spec = np.abs(np.fft.rfft(sig[:N] * np.hanning(N)))
freqs = np.fft.rfftfreq(N, 1 / fs)
ax[1].plot(freqs, 20 * np.log10(spec / spec.max() + 1e-9))
ax[1].set_xlim(0, 5000); ax[1].set_ylim(-80, 5)
ax[1].set_xlabel('Hz'); ax[1].set_ylabel('dB'); ax[1].set_title('FFT')

plt.tight_layout()
plt.savefig('carrier.png', dpi=100)
plt.show()
