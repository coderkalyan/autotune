import threading
import serial

from pitch_utils import lag_to_hz, nearest_note_hz

NUM_BYTES = 128
PAYLOAD_BITS = NUM_BYTES * 7  # 896
PAYLOAD_BYTES = PAYLOAD_BITS // 8  # 112

# Payload layout (896 bits, MSB first):
#   [895:886] 10-bit lag
#   [885]     1-bit  autocorrelation confidence
#   [884:21]  32 × 27-bit Q3.24 fixed_t vocode bands
#   [20:19]   2-bit  mode (MUTE=0, PASSTHROUGH=1, AUTOTUNE=2, VOCODE=3)
#   [18]      vad_active
#   [17]      vad_voiced
#   [16]      dac_full
#   [15]      adc_empty
#   [14]      config_done
#   [13]      config_err
#   [12:0]    padding

FIXED_MASK = (1 << 27) - 1
FIXED_SIGN = 1 << 26


def decode_payload(buf: list[int]) -> int:
    """Reassemble 128 framed bytes (7 data bits each) into a 896-bit integer."""
    bits = 0
    for b in buf:
        bits = (bits << 7) | (b & 0x7F)
    return bits


def unpack_payload(bits: int) -> dict:
    """Extract all fields from a 896-bit payload integer."""
    lag = (bits >> 886) & 0x3FF
    valid = (bits >> 885) & 1

    bands = []
    for j in range(32):
        shift = 884 - j * 27 - 26  # LSB position of band j
        raw = (bits >> shift) & FIXED_MASK
        if raw & FIXED_SIGN:
            raw -= 1 << 27
        bands.append(raw)

    mode = (bits >> 19) & 0x3
    vad_active = (bits >> 18) & 1
    vad_voiced = (bits >> 17) & 1
    dac_full = (bits >> 16) & 1
    adc_empty = (bits >> 15) & 1
    config_done = (bits >> 14) & 1
    config_err = (bits >> 13) & 1

    to_return = {
        "lag": lag,
        "valid": valid,
        "vocode_bands": bands,
        "mode": mode,
        "vad_active": vad_active,
        "vad_voiced": vad_voiced,
        "dac_full": dac_full,
        "adc_empty": adc_empty,
        "config_done": config_done,
        "config_err": config_err,
    }

    # print(to_return)

    return to_return


class Parser:
    """128-byte UART packet parser.

    Packet format (from rtl/uart_tx_wrapper.sv):
      128 bytes, MSB of each byte is a framing bit:
        byte 0:     MSB=1 (start), lower 7 bits = payload[895:889]
        byte 1-127: MSB=0, lower 7 bits = next 7 payload bits
      Total payload: 896 bits.
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
        bits = decode_payload(buf)
        fields = unpack_payload(bits)

        detected = None
        corrected = None
        if fields["valid"] and fields["lag"] != 0:
            detected = lag_to_hz(fields["lag"])
            corrected = nearest_note_hz(fields["lag"])

        self._on_reading(detected, corrected, fields)


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

    def _on_reading(
        self, detected_hz: float | None, corrected_hz: float | None, fields: dict
    ) -> None:
        with self._lock:
            self._latest = {
                "detected_hz": detected_hz,
                "corrected_hz": corrected_hz,
                "mode": fields["mode"],
                "vad_active": bool(fields["vad_active"]),
                "vad_voiced": bool(fields["vad_voiced"]),
                "dac_full": bool(fields["dac_full"]),
                "adc_empty": bool(fields["adc_empty"]),
                "config_done": bool(fields["config_done"]),
                "config_err": bool(fields["config_err"]),
                "vocode_bands": [v / (1 << 24) for v in fields["vocode_bands"]],
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

    def capture(detected, corrected, fields):
        results.append((detected, corrected))

    def make_packet(
        valid: bool,
        lag: int,
        bands=None,
        mode=0,
        vad_active=0,
        vad_voiced=0,
        dac_full=0,
        adc_empty=0,
        config_done=0,
        config_err=0,
    ) -> list[int]:
        """Build a 128-byte framed packet from fields."""
        bits = 0
        bits |= (lag & 0x3FF) << 886
        bits |= (int(valid) & 1) << 885
        if bands:
            for j, b in enumerate(bands):
                shift = 884 - j * 27 - 26
                bits |= (b & FIXED_MASK) << shift
        bits |= (mode & 0x3) << 19
        bits |= (vad_active & 1) << 18
        bits |= (vad_voiced & 1) << 17
        bits |= (dac_full & 1) << 16
        bits |= (adc_empty & 1) << 15
        bits |= (config_done & 1) << 14
        bits |= (config_err & 1) << 13
        # Split into 128 groups of 7 bits, MSB-first
        packet = []
        for i in range(NUM_BYTES):
            shift = (NUM_BYTES - 1 - i) * 7
            seven = (bits >> shift) & 0x7F
            if i == 0:
                seven |= 0x80
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

    print("Test 4 — round-trip all fields")
    test_bands = [((i * 1000) & FIXED_MASK) for i in range(32)]
    pkt = make_packet(
        True,
        200,
        bands=test_bands,
        mode=3,
        vad_active=1,
        vad_voiced=0,
        dac_full=1,
        adc_empty=0,
        config_done=1,
        config_err=1,
    )
    bits = decode_payload(pkt)
    f = unpack_payload(bits)
    assert f["lag"] == 200
    assert f["valid"] == 1
    assert f["mode"] == 3
    assert f["vad_active"] == 1
    assert f["vad_voiced"] == 0
    assert f["dac_full"] == 1
    assert f["adc_empty"] == 0
    assert f["config_done"] == 1
    assert f["config_err"] == 1
    for i in range(32):
        assert f["vocode_bands"][i] == test_bands[i], f"band {i} mismatch"
    print("  All fields round-tripped  OK")

    print("All tests passed.")
