import struct
import threading
import serial

from pitch_utils import lag_to_hz, nearest_note_hz

NUM_BYTES = 128
PAYLOAD_BITS = NUM_BYTES * 7  # 896
PAYLOAD_BYTES = PAYLOAD_BITS // 8  # 112


class Parser:
    """128-byte UART packet parser.

    Packet format (from rtl/uart_tx_wrapper.sv):
      128 bytes, MSB of each byte is a framing bit:
        byte 0:   MSB=1 (start), lower 7 bits = payload[895:889]
        byte 1-127: MSB=0, lower 7 bits = next 7 payload bits
      Total payload: 896 bits (112 bytes).

    Payload layout (packed big-endian):
      bit 895:    valid
      bits 894:10: (unused)
      bits 9:0:   pitch_period (lag)

    After reassembling the 896-bit payload into 112 bytes, we unpack with
    struct as big-endian: 1-bit valid in the MSB of the first byte, and a
    10-bit lag in the last two bytes.
    """

    def __init__(self, on_reading):
        self._on_reading = on_reading
        self._buf: list[int] = []

    def parse_byte(self, byte: int) -> None:
        is_start = (byte & 0x80) != 0

        if len(self._buf) == 0:
            if not is_start:
                return
            self._buf.append(byte)
        else:
            if is_start:
                self._buf = [byte]
                return
            self._buf.append(byte)
            if len(self._buf) == NUM_BYTES:
                self._process_packet(self._buf)
                self._buf = []

    def _process_packet(self, buf: list[int]) -> None:
        payload = self._decode_payload(buf)
        # 112 bytes: valid is MSB of first byte, lag is lower 10 bits of last 2 bytes
        #   byte layout: [0] = {valid, 6'b0, ...}, ... [110:111] = pitch_period
        # Unpack first byte and last two bytes; ignore the middle.
        valid = (payload[0] >> 7) & 1
        if not valid:
            return

        lag = struct.unpack(">H", payload[-2:])[0] & 0x3FF
        if lag == 0:
            return

        detected = lag_to_hz(lag)
        corrected = nearest_note_hz(lag)

        if detected is not None:
            self._on_reading(detected, corrected)

    @staticmethod
    def _decode_payload(buf: list[int]) -> bytes:
        """Reassemble 128 framed bytes (7 data bits each) into 112 payload bytes."""
        # Concatenate the 7 LSBs of each byte into a 896-bit integer
        bits = 0
        for b in buf:
            bits = (bits << 7) | (b & 0x7F)
        return bits.to_bytes(PAYLOAD_BYTES, byteorder="big")


class UARTParser:
    """Background thread that reads from a shared serial port and parses
    pitch packets. Consumers call get_latest() to retrieve the most recent
    reading without blocking.
    """

    def __init__(self, ser: serial.Serial):
        self._ser = ser
        self._lock = threading.Lock()
        self._latest: dict | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

    def start(self) -> None:
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=2.0)

    def get_latest(self) -> dict | None:
        with self._lock:
            return dict(self._latest) if self._latest else None

    def _on_reading(self, detected_hz: float, corrected_hz: float | None) -> None:
        with self._lock:
            self._latest = {
                "detected_hz": detected_hz,
                "corrected_hz": corrected_hz,
            }

    def _run(self) -> None:
        parser = Parser(self._on_reading)
        while not self._stop_event.is_set():
            try:
                data = self._ser.read(64)
                for b in data:
                    parser.parse_byte(b)
            except Exception as e:
                print(f"[uart_reader] serial error: {e}")
                break


if __name__ == "__main__":
    results = []

    def capture(detected, corrected):
        results.append((detected, corrected))

    def make_packet(valid: bool, lag: int) -> list[int]:
        """Build a 128-byte framed packet from valid + lag."""
        payload_int = 0
        if valid:
            payload_int |= 1 << (PAYLOAD_BITS - 1)
        payload_int |= lag & 0x3FF
        # Split into 128 groups of 7 bits, MSB-first
        packet = []
        for i in range(NUM_BYTES):
            shift = (NUM_BYTES - 1 - i) * 7
            seven = (payload_int >> shift) & 0x7F
            if i == 0:
                seven |= 0x80  # start bit
            packet.append(seven)
        return packet

    parser = Parser(on_reading=capture)

    print("Test 1 — valid packet, lag=109 (A4 ~440 Hz)")
    for b in make_packet(True, 109):
        parser.parse_byte(b)
    assert results, "No reading produced"
    d, c = results[-1]
    assert abs(d - 440.37) < 1.0, f"detected_hz wrong: {d}"
    print(f"  detected_hz={d:.2f}  corrected_hz={c:.2f}  OK")

    print("Test 2 — invalid packet (valid=0), should produce no reading")
    before = len(results)
    for b in make_packet(False, 109):
        parser.parse_byte(b)
    assert len(results) == before, "Should not emit reading for invalid packet"
    print("  No reading emitted  OK")

    print("Test 3 — packet with lag=183 (C4 ~262 Hz)")
    for b in make_packet(True, 183):
        parser.parse_byte(b)
    d, c = results[-1]
    assert abs(d - 262.30) < 1.0, f"detected_hz wrong: {d}"
    print(f"  detected_hz={d:.2f}  corrected_hz={c:.2f}  OK")

    print("All tests passed.")
