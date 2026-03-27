"""
gen_verilog.py
Generates two Verilog blocks for pitch detection at Fs = 48000 Hz:
  1. always_comb if-else chain: in_lag -> nearest_note_lag
  2. case statement:            nearest_note_lag -> HEXNOTE

Octave convention (confirmed from original RTL):
  oct_index = (MIDI // 12) - 2
  C4 (MIDI 60) -> oct_index=3 -> FOUR
  A4 (MIDI 69) -> oct_index=3 -> FOUR  (440 Hz shows as A4)
  C5 (MIDI 72) -> oct_index=4 -> FIVE

Sharp encoding: {S, <natural_note_below>, octave}
  C# -> {S, C, oct},  G# -> {S, G, oct},  A# -> {S, A, oct}
"""

import math

# ── Config ────────────────────────────────────────────────────────────────────
FS        = 48000
MIDI_MIN  = 32
MIDI_MAX  = 95
LAG_BITS  = 10
OUT_FILE  = "nearest_note_lag_out.sv"

# ── Lookup tables ─────────────────────────────────────────────────────────────

# Pitch class 0-11 -> (is_sharp, letter_token, note_name)
CHROMATIC = [
    (False, "C",  "C"),    # 0
    (True,  "C",  "C#"),   # 1  -> {S, C, oct}
    (False, "D",  "D"),    # 2
    (True,  "D",  "D#"),   # 3  -> {S, D, oct}
    (False, "E",  "E"),    # 4
    (False, "F",  "F"),    # 5
    (True,  "F",  "F#"),   # 6  -> {S, F, oct}
    (False, "G",  "G"),    # 7
    (True,  "G",  "G#"),   # 8  -> {S, G, oct}
    (False, "A",  "A"),    # 9
    (True,  "A",  "A#"),   # 10 -> {S, A, oct}
    (False, "B",  "B"),    # 11
]

# oct_index = (MIDI // 12) - 2
OCT_TOKENS = {
    0: "ONE",  1: "TWO",   2: "THREE", 3: "FOUR",
    4: "FIVE", 5: "SIX",   6: "SEVEN", 7: "EIGHT",
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def midi_freq(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)

def freq_lag(f):
    return round(FS / f)

def geomean_floor(a, b):
    """Logarithmic midpoint between two lags (floor of geometric mean)."""
    return math.floor(math.sqrt(a * b))

# ── Build note table ──────────────────────────────────────────────────────────

notes = []
for m in range(MIDI_MIN, MIDI_MAX + 1):
    f   = midi_freq(m)
    lag = freq_lag(f)

    is_sharp, letter, note_name = CHROMATIC[m % 12]
    oct_index   = (m // 12) - 2   # used for OCT_TOKENS lookup
    oct_display = oct_index + 1   # human-readable octave number (A4=440Hz, C4=middle C)
    oct_token   = OCT_TOKENS[oct_index]

    # Threshold: geometric mean of this note's lag and the next-lower note's lag
    lag_lower = freq_lag(midi_freq(m + 1))
    threshold = geomean_floor(lag, lag_lower)

    notes.append({
        "midi":      m,
        "freq":      f,
        "lag":       lag,
        "threshold": threshold,
        "is_sharp":  is_sharp,
        "letter":    letter,
        "name":      note_name,
        "oct":       oct_display,
        "oct_token": oct_token,
    })

# ── Generate Block 1: if-else threshold chain ─────────────────────────────────

def gen_threshold_block():
    B = LAG_BITS
    lines = [
        "    always_comb begin",
        f"        // Threshold = floor(sqrt(lag[n] * lag[n-1])) — logarithmic midpoint between semitones.",
        f"        // Fs = {FS} Hz.  Ordered from largest lag (lowest pitch) to smallest.",
    ]
    for i, n in enumerate(notes):
        thr     = n["threshold"]
        lag     = n["lag"]
        label   = f"{n['name']}{n['oct']}"
        comment = f"// MIDI {n['midi']:>2}  {label:<5}  ~{n['freq']:.2f} Hz"
        cond    = f"if (in_lag >= {B}'d{thr})" if i == 0 else f"else if (in_lag >= {B}'d{thr})"
        lines.append(f"         {cond:<35} nearest_note_lag = {B}'d{lag}; {comment}")

    last = notes[-1]
    lines.append(
        f"        else                                       nearest_note_lag = {B}'d{last['lag']}; "
        f"// MIDI {last['midi']}  {last['name']}{last['oct']} (above range)"
    )
    lines.append("    end")
    return "\n".join(lines)

# ── Generate Block 2: case statement ─────────────────────────────────────────

def gen_case_block():
    B = LAG_BITS
    lines = ["    case (nearest_note_lag)"]
    for n in notes:
        lag       = n["lag"]
        sharp_tok = "S   " if n["is_sharp"] else "NONE"
        oct_tok   = n["oct_token"]
        letter    = n["letter"]
        label     = f"{n['name']}{n['oct']}"
        lines.append(
            f"        {B}'d{lag:<4}: HEXNOTE = {{{sharp_tok}, {letter:<2}, {oct_tok:<6}}}; // {label}"
        )
    lines.append("        default: HEXNOTE = {NONE, NONE, NONE};")
    lines.append("    endcase")
    return "\n".join(lines)

# ── Print & write ─────────────────────────────────────────────────────────────

threshold_block = gen_threshold_block()
case_block      = gen_case_block()

output = "\n\n".join([
    "// ── Block 1: in_lag -> nearest_note_lag ─────────────────────────────────────",
    threshold_block,
    "// ── Block 2: nearest_note_lag -> HEXNOTE ───────────────────────────────────",
    case_block,
])

print(output)

with open(OUT_FILE, "w") as f:
    f.write(output + "\n")

print(f"\n// Written to {OUT_FILE}")
