import numpy as np
import matplotlib.pyplot as plt

# Params
fs = 48000
dur = 10
f0 = 440

# Mellow drawbars (dipped mids, moderate top)
drawbars = [8, 5, 8, 4, 6, 5, 3, 5, 4]
ratios = [0.5, 1.5, 1, 2, 3, 4, 5, 6, 8]

# Maj9 voicing with sub-octaves and fills
# Ratios relative to f0: sub-sub, sub, 5th below, root, 5th, octave, 9th, 3rd+oct, 5th+oct
chord = [0.125, 0.25, 0.375, 0.5, 0.75, 1.0, 1.125, 1.25, 1.5, 2.0]
amps  = [0.6,   0.8,  0.5,   0.9, 0.6,  1.0, 0.4,   0.5,  0.6, 0.35]

# 5-voice ensemble detune per note (cents)
detunes_cents = [-7, -3, 0, 3, 7]

freqs = [f0 * r for r in chord]
t = np.arange(int(fs * dur)) / fs
sig = np.zeros_like(t)

for f, amp in zip(freqs, amps):
    for dc in detunes_cents:
        fd = f * (2 ** (dc / 1200))
        voice = sum((d / 8) * np.sin(2 * np.pi * fd * r * t)
                    for d, r in zip(drawbars, ratios))
        sig += voice * amp / len(detunes_cents)

sig = sig / np.max(np.abs(sig))

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
