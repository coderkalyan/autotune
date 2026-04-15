"""Generate a 7-bit → 7-bit exponential volume LUT.

Uses curve: f(x) = a * exp(b * x)
with coefficients chosen so that:
  f(0)   = 1     (minimum nonzero output)
  f(127) = 127   (full scale)

Solving:  a = 1,  b = ln(127) / 127

Input 0 is hardcoded to output 0 (mute).

Output: rtl/log_volume.mem (128 lines of 2-digit hex, one per input value)
"""

import math
import os

ENTRIES = 128
MAX_OUT = 127

def generate():
    # f(x) = a * exp(b * x), a = 1, b = ln(127)/127
    a = 1.0
    b = math.log(MAX_OUT) / MAX_OUT

    lut = [0] * ENTRIES
    for i in range(1, ENTRIES):
        out = a * math.exp(b * i)
        lut[i] = max(1, min(MAX_OUT, round(out)))
    lut[0] = 0
    lut[MAX_OUT] = MAX_OUT

    return lut

def main():
    lut = generate()

    # Print table for verification
    for i, v in enumerate(lut):
        db = -math.inf if v == 0 else 20 * math.log10(v / 64)
        print(f"  {i:3d} -> {v:3d}  ({db:+.1f} dB)")

    out_path = os.path.join(os.path.dirname(__file__), "..", "rtl", "log_volume.mem")
    with open(out_path, "w") as f:
        for v in lut:
            f.write(f"{v:02x}\n")
    print(f"\nWrote {len(lut)} entries to {out_path}")

if __name__ == "__main__":
    main()
