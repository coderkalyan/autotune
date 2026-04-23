import numpy as np

M = 10          # address bits
entries = 2**(M + 2)  # 1024 * 4 full wave entries (since we only keep quarter)

phase = np.arange(entries) / entries  # 0 to 1 (exclusive)
sine_full = np.sin(2 * np.pi * phase)

# Scale to Q11.16
scale = 1 << 16
sine_int = np.round(sine_full * scale).astype(np.int32)

# Only store quarter wave (first 256 entries)
# quarter = sine_int[:entries//4]
quarter = sine_int

print(quarter)

# Write out as Verilog ROM init or MIF file
with open("sine.mem", "w") as f:
    for val in quarter:
        # Mask to 32 bits to handle negative numbers and padding correctly
        hex_val = format(int(val) & 0xFFFFFFFF, '08x')
        f.write(f"{hex_val}\n")
