import threading
import serial

from pitch_utils import lag_to_hz, nearest_note_hz


class Parser:
    """4-byte UART packet parser ported from py/mock_uart_rx.py.

    Packet layout (from rtl/uart_tx_wrapper.sv):
      byte 0: {1'b1, valid, 6'd0}   — MSB=1 marks start
      byte 1: {1'b0, 7'd0}
      byte 2: {1'b0, 4'd0, pitch_period[9:7]}
      byte 3: {1'b0, pitch_period[6:0]}
    """

    def __init__(self, on_reading):
        # on_reading(detected_hz, corrected_hz) called on each valid packet
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
                # Unexpected start — reset and begin new packet
                self._buf = [byte]
                return
            self._buf.append(byte)
            if len(self._buf) == 4:
                self._process_packet(self._buf)
                self._buf = []

    def _process_packet(self, buf: list[int]) -> None:
        valid = (buf[0] >> 6) & 1
        if not valid:
            return

        lag = ((buf[2] & 0x7F) << 7 | (buf[3] & 0x7F)) & 0x3FF
        if lag == 0:
            return

        detected = lag_to_hz(lag)
        corrected = nearest_note_hz(lag)

        if detected is not None:
            self._on_reading(detected, corrected)


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
    # Standalone verification: feed pre-baked packet bytes through Parser directly.
    # Packet encoding: valid=1, lag=109 (A4, ~440 Hz)
    #   byte 0: 0b11000000 = 0xC0  (start=1, valid=1)
    #   byte 1: 0b00000000 = 0x00
    #   byte 2: lag[9:7]=0  → {1'b0, 4'd0, 3'd0} = 0x00
    #   byte 3: lag[6:0]=109 → {1'b0, 7'd109}    = 0x6D
    results = []

    def capture(detected, corrected):
        results.append((detected, corrected))

    parser = Parser(on_reading=capture)

    print("Test 1 — valid packet, lag=109 (A4 ~440 Hz)")
    for b in [0xC0, 0x00, 0x00, 0x6D]:
        parser.parse_byte(b)
    assert results, "No reading produced"
    d, c = results[-1]
    assert abs(d - 440.37) < 1.0, f"detected_hz wrong: {d}"
    assert abs(c - 440.37) < 1.0, f"corrected_hz wrong: {c}"
    print(f"  detected_hz={d:.2f}  corrected_hz={c:.2f}  OK")

    print("Test 2 — invalid packet (valid bit=0), should produce no reading")
    before = len(results)
    for b in [0x80, 0x00, 0x00, 0x6D]:  # start=1, valid=0
        parser.parse_byte(b)
    assert len(results) == before, "Should not emit reading for invalid packet"
    print("  No reading emitted  OK")

    print("Test 3 — packet with lag=183 (C4 ~262 Hz)")
    # lag=183: byte2 = {0, 0000, 010} = 0x02, byte3 = {0, 1010111} = 0x57
    # lag=183 = 0b10110111; [9:7]=001=1, [6:0]=0110111=55 → byte2=0x01, byte3=0x37
    lag = 183
    b2 = (lag >> 7) & 0x07
    b3 = lag & 0x7F
    for b in [0xC0, 0x00, b2, b3]:
        parser.parse_byte(b)
    d, c = results[-1]
    assert abs(d - 262.30) < 1.0, f"detected_hz wrong: {d}"
    print(f"  detected_hz={d:.2f}  corrected_hz={c:.2f}  OK")

    print("All tests passed.")
