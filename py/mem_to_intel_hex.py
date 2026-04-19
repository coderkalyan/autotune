"""Convert a flat .mem file (one hex word per line) into Intel HEX format
suitable for the Quartus altsyncram `init_file` parameter.

Usage: python mem_to_intel_hex.py INPUT.mem [OUTPUT.hex] [--word-bytes N]

The Quartus ROM IP expects byte-addressed Intel HEX with big-endian byte
order within each word (MSB byte first).
"""

import argparse
import sys
from pathlib import Path


def parse_mem(path: Path, word_bytes: int) -> list[int]:
    max_val = 1 << (word_bytes * 8)
    words: list[int] = []
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        s = raw.strip()
        if not s or s.startswith("//") or s.startswith("#"):
            continue
        # strip inline comments
        for sep in ("//", "#"):
            if sep in s:
                s = s.split(sep, 1)[0].strip()
        if not s:
            continue
        try:
            v = int(s, 16)
        except ValueError as e:
            raise SystemExit(f"{path}:{lineno}: invalid hex '{raw}'") from e
        if v < 0 or v >= max_val:
            raise SystemExit(
                f"{path}:{lineno}: value 0x{v:X} exceeds {word_bytes}-byte word"
            )
        words.append(v)
    return words


def emit_record(out, byte_addr: int, rec_type: int, data: bytes) -> None:
    # Intel HEX record: :LL AAAA TT [DD..] CC
    ll = len(data)
    hi = (byte_addr >> 8) & 0xFF
    lo = byte_addr & 0xFF
    body = bytes([ll, hi, lo, rec_type]) + data
    checksum = (-sum(body)) & 0xFF
    out.write(":" + body.hex().upper() + f"{checksum:02X}\n")


def write_intel_hex(
    words: list[int], out_path: Path, word_bytes: int, words_per_record: int = 8
) -> None:
    with out_path.open("w") as out:
        last_upper = -1
        for i in range(0, len(words), words_per_record):
            chunk = words[i : i + words_per_record]
            byte_addr = i * word_bytes
            upper = byte_addr >> 16
            if upper != last_upper:
                # Extended linear address record (type 04) for >64K spaces
                ext = bytes([(upper >> 8) & 0xFF, upper & 0xFF])
                emit_record(out, 0, 0x04, ext)
                last_upper = upper
            data = bytearray()
            for w in chunk:
                # Big-endian byte order within each word (MSB first).
                for shift in range((word_bytes - 1) * 8, -1, -8):
                    data.append((w >> shift) & 0xFF)
            emit_record(out, byte_addr & 0xFFFF, 0x00, bytes(data))
        # EOF record
        out.write(":00000001FF\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path, help=".mem file (one hex word per line)")
    ap.add_argument(
        "output",
        nargs="?",
        type=Path,
        help="output .hex (defaults to input with .hex suffix)",
    )
    ap.add_argument(
        "--word-bytes",
        type=int,
        default=2,
        help="bytes per word (default 2 = 16-bit ROM)",
    )
    ap.add_argument(
        "--words-per-record",
        type=int,
        default=8,
        help="words per Intel HEX data record (default 8 = 16 bytes)",
    )
    args = ap.parse_args()

    out = args.output or args.input.with_suffix(".hex")
    words = parse_mem(args.input, args.word_bytes)
    write_intel_hex(words, out, args.word_bytes, args.words_per_record)
    print(
        f"{args.input} -> {out}: {len(words)} x {args.word_bytes*8}-bit words",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
