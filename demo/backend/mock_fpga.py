"""Mock FPGA UART transmitter for the harmony demo.

Sends framed 144-byte packets at ~30 Hz, mirroring the layout in
rtl/uart_tx_wrapper.sv (see demo/backend/uart_parser.py for field map).
Walks a melody through a key, emitting reasonable harmony / chord state
so HarmonyScreen is fully populated.

Linux setup (no demo code changes required):

    # 1) Create a virtual serial pair. Link the FPGA-facing end at the
    #    exact path main.py expects so the backend opens it unmodified.
    #    The /dev/ side needs root.
    sudo socat -d -d \\
        pty,raw,echo=0,link=/tmp/mock_fpga \\
        pty,raw,echo=0,link=/dev/cu.usbserial-FTA9O9VB

    # 2) In another terminal, run the mock writing to the other end:
    python demo/backend/mock_fpga.py --port /tmp/mock_fpga

    # 3) Start the demo backend + frontend as usual. Switch to Harmony
    #    mode in the UI; chord HUD + pitch wheel will animate.

If you'd rather avoid sudo, point socat's second link somewhere you can
write (e.g. /tmp/mock_fpga_be) and edit SERIAL_PORT in main.py to match.
"""

from __future__ import annotations

import argparse
import sys
import time

import serial

NUM_BYTES = 144
FIXED_MASK = (1 << 27) - 1
FS = 48000

# Mirror of pitch_utils._LAG_TO_NOTE keys.
LAG_LIST = [
    925, 873, 824, 778, 734, 693, 654, 617, 582, 550, 519, 490,
    462, 436, 412, 389, 367, 346, 327, 309, 291, 275, 259, 245,
    231, 218, 206, 194, 183, 173, 163, 154, 146, 137, 130, 122,
    116, 109, 103,  97,  92,  87,  82,  77,  73,  69,  65,  61,
     58,  55,  51,  49,  46,  43,  41,  39,  36,  34,  32,  31,
     29,  27,  26,  24,
]

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def midi_to_lag(midi: int) -> int:
    """Snap a MIDI note to the nearest valid autocorrelation lag."""
    if midi <= 0:
        return 0
    hz = 440.0 * (2.0 ** ((midi - 69) / 12.0))
    return min(LAG_LIST, key=lambda L: abs(FS / L - hz))


def harmonize(midi: int, tonic_pc: int, minor: bool, degrees_up: int) -> int:
    """Move `degrees_up` scale degrees above `midi` within the active key.

    Falls back to a parallel third/fifth if melody is off-scale.
    """
    scale = MINOR if minor else MAJOR
    pc = (midi - tonic_pc) % 12
    if pc in scale:
        deg = scale.index(pc)
        interval = scale[(deg + degrees_up) % 7] - scale[deg]
        if interval <= 0:
            interval += 12
        return midi + interval
    return midi + (4 if degrees_up == 2 else 7)


def make_packet(**f) -> bytes:
    """Build one framed UART packet (NUM_BYTES bytes, MSB of byte 0 = start)."""
    bits = 0
    bits |= (f.get("lag", 0) & 0x3FF) << 998
    bits |= (f.get("valid", 0) & 1) << 997
    for j, b in enumerate(f.get("vocode_bands", [0] * 32)):
        bits |= (b & FIXED_MASK) << (996 - j * 27 - 26)
    bits |= (f.get("mode", 0) & 0x7) << 130
    bits |= (f.get("vad_active", 0) & 1) << 129
    bits |= (f.get("vad_voiced", 0) & 1) << 128
    bits |= (f.get("dac_full", 0) & 1) << 127
    bits |= (f.get("adc_empty", 0) & 1) << 126
    bits |= (f.get("config_done", 0) & 1) << 125
    bits |= (f.get("config_err", 0) & 1) << 124
    bits |= (f.get("target_lag", 0) & 0x3FF) << 114
    bits |= (f.get("melody_midi", 0) & 0x7F) << 107
    bits |= (f.get("held_midi", 0) & 0x7F) << 100
    bits |= (f.get("any_note_pressed", 0) & 1) << 99
    bits |= (f.get("harm1_midi", 0) & 0x7F) << 92
    bits |= (f.get("harm2_midi", 0) & 0x7F) << 85
    bits |= (f.get("harm_tonic", 0) & 0xF) << 81
    bits |= (f.get("harm_mode", 0) & 1) << 80
    bits |= (f.get("chord_state", 0) & 0x7) << 77
    bits |= (f.get("in_scale", 0) & 1) << 76

    out = bytearray(NUM_BYTES)
    for i in range(NUM_BYTES):
        seven = (bits >> ((NUM_BYTES - 1 - i) * 7)) & 0x7F
        if i == 0:
            seven |= 0x80
        out[i] = seven
    return bytes(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", required=True, help="Serial/PTY path to write to")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--rate", type=float, default=30.0, help="Packets per second")
    ap.add_argument("--tonic", type=int, default=0, help="Key tonic (0=C .. 11=B)")
    ap.add_argument("--minor", action="store_true", help="Minor key (default major)")
    ap.add_argument("--note-ms", type=float, default=500.0, help="Note duration ms")
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=1)
    print(
        f"[mock_fpga] {args.port} @ {args.baud} baud, {args.rate} pkt/s, "
        f"key={'minor' if args.minor else 'major'} tonic_pc={args.tonic}"
    )

    scale = MINOR if args.minor else MAJOR
    base = 60 + args.tonic  # C4-relative
    melody_up = [base + s for s in scale] + [base + 12]
    melody_seq = melody_up + list(reversed(melody_up[:-1]))

    note_dur_s = args.note_ms / 1000.0
    period = 1.0 / args.rate
    t0 = time.monotonic()
    pkt_count = 0

    while True:
        now = time.monotonic() - t0

        idx = int(now / note_dur_s) % len(melody_seq)
        melody = melody_seq[idx]

        # Brief unvoiced gap at the tail of each note (realism for VAD).
        frac = (now / note_dur_s) - int(now / note_dur_s)
        voiced = frac < 0.92

        h1 = harmonize(melody, args.tonic, args.minor, 2)  # third
        h2 = harmonize(melody, args.tonic, args.minor, 4)  # fifth

        # Markov FSM mock: rotate 0..6 every 700 ms.
        chord = int(now / 0.7) % 7

        lag = midi_to_lag(melody) if voiced else 0
        in_scale = ((melody - args.tonic) % 12) in scale

        pkt = make_packet(
            lag=lag,
            valid=1 if voiced else 0,
            mode=3,  # HARMONY
            vad_active=1,
            vad_voiced=1 if voiced else 0,
            dac_full=0,
            adc_empty=0,
            config_done=1,
            config_err=0,
            target_lag=lag,
            melody_midi=melody if voiced else 0,
            held_midi=base,
            any_note_pressed=1,
            harm1_midi=h1 if voiced else 0,
            harm2_midi=h2 if voiced else 0,
            harm_tonic=args.tonic & 0xF,
            harm_mode=1 if args.minor else 0,
            chord_state=chord,
            in_scale=1 if in_scale else 0,
        )
        ser.write(pkt)
        pkt_count += 1

        nxt = t0 + pkt_count * period
        sleep = nxt - time.monotonic()
        if sleep > 0:
            time.sleep(sleep)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
