from scipy.signal import remez
import numpy as np
import os

N = 63
taps = remez(N, [0.05, 0.45], [1], type='hilbert', fs=1.0)

# A 63-tap Type-III Hilbert FIR has odd symmetry with h[center]=0 and zero
# at all even offsets from center (index 31).  Non-zero taps therefore sit at
# even absolute indices: h[0], h[2], h[4], ..., h[62]  (32 taps total).
center = N // 2   # 31

# Quick sanity check: odd absolute indices should be ~zero
max_zero_err = max(abs(taps[i]) for i in range(1, N, 2))
print(f"Max value at expected-zero (odd) taps: {max_zero_err:.2e}  (should be ~0)")

# Extract the 32 non-zero taps in order
nz_taps = taps[::2]   # h[0], h[2], ..., h[62]

# Convert to Q11.16 fixed-point  (fixed_t = logic signed [26:0])
SCALE = 1 << 16
taps_q = np.round(nz_taps * SCALE).astype(np.int32)

print(f"\n{'coeffs':>8}  {'tap':>5}  {'float':>12}  {'Q11.16':>8}  {'hex (32-bit)':>12}")
for i, (t, tq) in enumerate(zip(nz_taps, taps_q)):
    print(f"[{i:2d}]  h[{2*i:2d}]  {t:+12.8f}  {int(tq):8d}  0x{int(tq) & 0xFFFFFFFF:08x}")

# Write to rtl/hilbert.mem  (32-bit hex entries, matching sine.mem / hanning.hex format)
script_dir = os.path.dirname(os.path.abspath(__file__))
mem_path = os.path.join(script_dir, '..', 'rtl', 'hilbert.mem')

with open(mem_path, 'w') as f:
    for tq in taps_q:
        f.write(f"{int(tq) & 0xFFFFFFFF:08x}\n")

print(f"\nWritten {len(taps_q)} entries to {os.path.normpath(mem_path)}")
