import numpy as np

N = 4096
window = np.hanning(N)
normalized_window = window / np.max(window)

# Convert to Q11.16: Scale by 2^16 and convert to integer
# 11 bits for integer (including sign), 16 bits for fraction
scale = 1 << 16
fixed_point_values = (normalized_window * scale).astype(np.int32)

with open("hanning.hex", "w") as f:
    for val in fixed_point_values:
        # Mask to 32 bits to handle negative numbers and padding correctly
        hex_val = format(int(val) & 0xFFFFFFFF, '08x')
        f.write(f"{hex_val}\n")
