
# TODO: fill in names with actual file names
file_input = "twinkle.pcm"
file_output = "twinkle.hex"

output_eff = file_output

# MAX_COUNT = 5000
# cnt = 0
# with open(file_input, "rb") as f_in, open(output_eff, "w") as f_out:
#     while True:
#         b = f_in.read(2)   # 16-bit sample
#         if not b or cnt >= MAX_COUNT:
#             break
#         sample = int.from_bytes(b, byteorder="little", signed=True)
#         if sample == 0:
#             continue  # skip zero samples to save space
#         f_out.write(f"{sample & 0xFFFF:04x}\n")
#         cnt += 1

import math

# -----------------------------
# Configuration
# -----------------------------
fs = 48000          # sample rate (Hz)
freq = 440          # sine frequency (Hz)
duration = 1.0      # seconds
amplitude = 32767   # max for 16-bit signed

output_file = "sine_440hz_48k.hex"

# -----------------------------
# Generate samples
# -----------------------------
num_samples = int(fs * duration)

with open(output_file, "w") as f:
    for n in range(num_samples):
        # generate sine sample
        sample = int(amplitude * math.sin(2 * math.pi * freq * n / fs))

        # convert to 16-bit two’s complement hex
        hex_sample = format(sample & 0xFFFF, "04x")

        # write one sample per line
        f.write(hex_sample + "\n")