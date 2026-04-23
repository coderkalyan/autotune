#!/usr/bin/env python3
"""
mock_backend.py — reads MIDI from a physical keyboard and forwards it to the FPGA over serial.

Usage:
    python mock_backend.py                          # auto-detect MIDI port, use COM5
    python mock_backend.py --serial-port COM3
    python mock_backend.py --midi-port "Your Keyboard"
    python mock_backend.py --list-midi              # list available MIDI ports
"""

import argparse
import sys

import mido
import serial

SERIAL_PORT = "COM5"
BAUD = 31250

MODE_NAMES = {0x28: "MUTE", 0x29: "PASSTHROUGH", 0x2A: "AUTOTUNE", 0x2B: "VOCODE", 0x2C: "SYNTH"}
_SKIP_KEYWORDS = ("through", "midi through", "loopmidi")


def pick_midi_port(requested: str) -> str | None:
    available = mido.get_input_names()
    if not available:
        return None
    if requested:
        for name in available:
            if name == requested or requested.lower() in name.lower():
                return name
        print(f"Port '{requested}' not found. Available: {available}")
        return None
    for name in available:
        if not any(kw in name.lower() for kw in _SKIP_KEYWORDS):
            return name
    return available[0]


def run(serial_port: str, midi_port_name: str) -> None:
    print(f"Opening serial {serial_port} @ {BAUD} baud...")
    ser = serial.Serial(serial_port, BAUD, timeout=1)

    print(f"Opening MIDI input '{midi_port_name}'...")
    with mido.open_input(midi_port_name) as port:
        print("Forwarding MIDI to FPGA. Ctrl+C to stop.\n")
        for msg in port:
            if msg.bytes() == [0xF8]:   # skip MIDI clock
                continue

            raw = bytes(msg.bytes())
            ser.write(raw)

            # Human-readable log
            if msg.type == "note_on" and msg.channel == 9:
                mode = MODE_NAMES.get(msg.note, f"pad={msg.note:#x}")
                print(f"  mode → {mode}")
            elif msg.type in ("note_on", "note_off") and msg.channel == 0:
                action = "ON " if (msg.type == "note_on" and msg.velocity > 0) else "OFF"
                print(f"  note {action} #{msg.note} vel={msg.velocity}")
            else:
                print(f"  {msg}")


def main() -> None:
    parser = argparse.ArgumentParser(description="MIDI → FPGA forwarder (Windows)")
    parser.add_argument("--list-midi",   action="store_true", help="List MIDI input ports and exit")
    parser.add_argument("--serial-port", default=SERIAL_PORT, help=f"COM port for FPGA (default: {SERIAL_PORT})")
    parser.add_argument("--midi-port",   default="",          help="MIDI input port name (default: auto-detect)")
    args = parser.parse_args()

    if args.list_midi:
        ports = mido.get_input_names()
        print("Available MIDI input ports:" if ports else "No MIDI input ports found.")
        for p in ports:
            print(f"  {p}")
        sys.exit(0)

    port_name = pick_midi_port(args.midi_port)
    if not port_name:
        print("No MIDI input port found. Connect a keyboard or use --midi-port.")
        sys.exit(1)

    try:
        run(args.serial_port, port_name)
    except KeyboardInterrupt:
        print("\nStopped.")
    except serial.SerialException as e:
        print(f"Serial error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
