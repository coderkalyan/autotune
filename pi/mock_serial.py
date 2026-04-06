#!/usr/bin/env python3
"""
Mock FPGA serial output for testing the web app without hardware.

Uses a Unix named pipe (FIFO) — no baud rate, no ioctl, no pyserial needed.

Usage (run in order):
  # 1. Create virtual serial port pair (keep terminal open):
  #    socat -d -d pty,raw,echo=0,link=/tmp/fpga_tx pty,raw,echo=0,link=/tmp/fpga_rx
  #
  # 2. Start the web app (from pi/ directory):
  #    SERIAL_PORT=/tmp/fpga_rx USE_FS=1 pnpm dev
  #
  # 3. Run this script (from pi/ directory):
  #    PORT=/tmp/fpga_tx python3 mock_serial.py
"""

import math
import os
import struct
import sys
import time

PORT = os.environ.get("PORT", "/tmp/fpga_pipe")
SAMPLE_RATE = 48000


def encode_packet(hz: float) -> bytes:
    """Pack a frequency into the 4-chunk FPGA packet format.

    Chunk 1: 1VDDDDDD  — MSB=1 (start), V=valid, period[26:21]
    Chunk 2: 0DDDDDDD  — period[20:14]
    Chunk 3: 0DDDDDDD  — period[13:7]
    Chunk 4: 0DDDDDDD  — period[6:0]
    """
    period_q = int((SAMPLE_RATE / hz) * 65536) & 0x07FFFFFF  # 27 bits
    chunk1 = 0x80 | (1 << 6) | ((period_q >> 21) & 0x3F)     # valid=1
    chunk2 =         (period_q >> 14) & 0x7F
    chunk3 =         (period_q >> 7)  & 0x7F
    chunk4 =          period_q        & 0x7F
    return bytes([chunk1, chunk2, chunk3, chunk4])


def sweep(t: float) -> float:
    """Slow sine sweep 100–600 Hz, period ~20 seconds."""
    return 350 + 250 * math.sin((t / 20) * 2 * math.pi)


def main() -> None:
    if not os.path.exists(PORT):
        print(f"Pipe {PORT!r} not found. Create it first:")
        print(f"  mkfifo {PORT}")
        sys.exit(1)

    print(f"Opening {PORT!r} — waiting for reader (start the Node server first)…")
    try:
        # open() blocks here until the Node server opens the other end for reading
        pipe = open(PORT, "wb", buffering=0)
    except OSError as e:
        print(f"Could not open {PORT}: {e}")
        sys.exit(1)

    print(f"Connected. Sending mock packets at 10 Hz  (Ctrl-C to stop)")
    t = 0.0
    try:
        while True:
            hz = sweep(t)
            pipe.write(encode_packet(hz))
            print(f"  {hz:.1f} Hz", end="\r")
            t += 0.1
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        pipe.close()


if __name__ == "__main__":
    main()
