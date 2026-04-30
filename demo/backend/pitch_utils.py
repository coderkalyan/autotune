FS = 48000
VOCAL_MIN_HZ = 80.0
VOCAL_MAX_HZ = 900.0

# Valid lag values and their note names, ported from py/mock_uart_rx.py.
# Keys are autocorrelation lag counts at Fs=48000; values are note Hz (= FS / lag).
_LAG_TO_NOTE = {
    925: "G#1", 873: "A1",  824: "A#1", 778: "B1",
    734: "C2",  693: "C#2", 654: "D2",  617: "D#2",
    582: "E2",  550: "F2",  519: "F#2", 490: "G2",
    462: "G#2", 436: "A2",  412: "A#2", 389: "B2",
    367: "C3",  346: "C#3", 327: "D3",  309: "D#3",
    291: "E3",  275: "F3",  259: "F#3", 245: "G3",
    231: "G#3", 218: "A3",  206: "A#3", 194: "B3",
    183: "C4",  173: "C#4", 163: "D4",  154: "D#4",
    146: "E4",  137: "F4",  130: "F#4", 122: "G4",
    116: "G#4", 109: "A4",  103: "A#4",  97: "B4",
     92: "C5",   87: "C#5",  82: "D5",   77: "D#5",
     73: "E5",   69: "F5",   65: "F#5",  61: "G5",
     58: "G#5",  55: "A5",   51: "A#5",  49: "B5",
     46: "C6",   43: "C#6",  41: "D6",   39: "D#6",
     36: "E6",   34: "F6",   32: "F#6",  31: "G6",
     29: "G#6",  27: "A6",   26: "A#6",  24: "B6",
}

# Precomputed: lag → Hz
LAG_TO_HZ: dict[int, float] = {lag: FS / lag for lag in _LAG_TO_NOTE}

# Sorted list of valid lag keys for fast nearest-lookup
_VALID_LAGS: list[int] = sorted(LAG_TO_HZ)


def midi_to_hz(midi: float) -> float:
    """Convert a MIDI note number to frequency in Hz (A4 = 69 = 440 Hz)."""
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def lag_to_hz(lag: int) -> float | None:
    """Convert a raw autocorrelation lag to frequency in Hz.

    Returns None if lag is 0 or the resulting frequency is outside the
    vocal range [VOCAL_MIN_HZ, VOCAL_MAX_HZ].
    """
    if lag <= 0:
        return None
    hz = FS / lag
    if hz < VOCAL_MIN_HZ or hz > VOCAL_MAX_HZ:
        return None
    return hz


def nearest_note_hz(lag: int) -> float | None:
    """Snap a raw lag to the nearest equal-temperament note frequency.

    Uses the same set of valid note lags as the FPGA's nearest_note_lut.sv.
    Returns None if lag is <= 0 or the snapped frequency is outside the
    vocal range.
    """
    if lag <= 0:
        return None
    best = min(_VALID_LAGS, key=lambda k: abs(k - lag))
    hz = LAG_TO_HZ[best]
    if hz < VOCAL_MIN_HZ or hz > VOCAL_MAX_HZ:
        return None
    return hz


if __name__ == "__main__":
    tests = [
        (109, "lag_to_hz(109)     ", 440.4, None),
        (40,  "lag_to_hz(40)      ", None,  None),   # 1200 Hz > VOCAL_MAX
        (48,  "lag_to_hz(48)      ", None,  None),   # 1000 Hz > VOCAL_MAX
        (0,   "lag_to_hz(0)       ", None,  None),
        (111, "nearest_note_hz(111)", None, 440.37),  # snaps to lag=109 (A4)
        (183, "nearest_note_hz(183)", None, 262.30),  # C4
    ]
    print(f"{'Test':<25}  {'Result':>10}  {'Expected':>10}  {'Pass':>5}")
    print("-" * 60)
    for lag, label, expected_direct, expected_note in tests:
        if expected_direct is not None or expected_note is None:
            result = lag_to_hz(lag)
            expected = expected_direct
        else:
            result = nearest_note_hz(lag)
            expected = expected_note

        if expected is None:
            ok = result is None
        else:
            ok = result is not None and abs(result - expected) < 1.0

        result_str = f"{result:.2f}" if result is not None else "None"
        exp_str = f"{expected:.2f}" if expected is not None else "None"
        print(f"{label:<25}  {result_str:>10}  {exp_str:>10}  {'OK' if ok else 'FAIL':>5}")
