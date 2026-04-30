import threading
import time
from collections import deque

import serial

from pitch_utils import lag_to_hz, nearest_note_hz

NUM_BYTES = 144
PAYLOAD_BITS = NUM_BYTES * 7  # 1008
PAYLOAD_BYTES = PAYLOAD_BITS // 8  # 126

# Payload layout (1008 bits, MSB first) — mirror of rtl/uart_tx_wrapper.sv:
#   [1007:998] 10-bit lag
#   [997]      1-bit  autocorrelation confidence
#   [996:133]  32 × 27-bit Q3.24 fixed_t vocode bands
#   [132:130]  3-bit  mode (MUTE=0, PASSTHROUGH=1, AUTOTUNE=2, HARMONY=3, VOCODE=4, SYNTH=5)
#   [129]      vad_active
#   [128]      vad_voiced
#   [127]      dac_full
#   [126]      adc_empty
#   [125]      config_done
#   [124]      config_err
#   [123:114]  10-bit target_lag
#   [113:107]  7-bit melody_midi (input to harmony_gen)
#   [106:100]  7-bit held_midi (priority-encoder MIDI of held keys)
#   [99]       any_note_pressed
#   [98:92]    7-bit harm1_midi
#   [91:85]    7-bit harm2_midi
#   [84:81]    4-bit harm_tonic (0=C..11=B)
#   [80]       harm_mode (0=major, 1=minor)
#   [79:77]    3-bit chord_state (Markov FSM state)
#   [76]       in_scale
#   [75:0]     padding

FIXED_MASK = (1 << 27) - 1
FIXED_SIGN = 1 << 26

PITCH_CLASS_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def decode_payload(buf: list[int]) -> int:
    """Reassemble framed bytes (7 data bits each) into a PAYLOAD_BITS-wide int."""
    bits = 0
    for b in buf:
        bits = (bits << 7) | (b & 0x7F)
    return bits


def unpack_payload(bits: int) -> dict:
    """Extract all fields from a 1008-bit payload integer."""
    lag = (bits >> 998) & 0x3FF
    valid = (bits >> 997) & 1

    bands = []
    for j in range(32):
        shift = 996 - j * 27 - 26  # LSB position of band j
        raw = (bits >> shift) & FIXED_MASK
        if raw & FIXED_SIGN:
            raw -= 1 << 27
        bands.append(raw)

    mode = (bits >> 130) & 0x7
    vad_active = (bits >> 129) & 1
    vad_voiced = (bits >> 128) & 1
    dac_full = (bits >> 127) & 1
    adc_empty = (bits >> 126) & 1
    config_done = (bits >> 125) & 1
    config_err = (bits >> 124) & 1
    target_lag = (bits >> 114) & 0x3FF

    melody_midi = (bits >> 107) & 0x7F
    held_midi = (bits >> 100) & 0x7F
    any_note_pressed = (bits >> 99) & 1
    harm1_midi = (bits >> 92) & 0x7F
    harm2_midi = (bits >> 85) & 0x7F
    harm_tonic = (bits >> 81) & 0xF
    harm_mode = (bits >> 80) & 1
    chord_state = (bits >> 77) & 0x7
    in_scale = (bits >> 76) & 1

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
        "target_lag": target_lag,
        "melody_midi": melody_midi,
        "held_midi": held_midi,
        "any_note_pressed": any_note_pressed,
        "harm1_midi": harm1_midi,
        "harm2_midi": harm2_midi,
        "harm_tonic": harm_tonic,
        "harm_mode": harm_mode,
        "chord_state": chord_state,
        "in_scale": in_scale,
    }

    return to_return


def midi_to_name(m: int) -> str:
    """Format MIDI number as e.g. 'A4'. Returns '' for 0 (sentinel)."""
    if m <= 0 or m > 127:
        return ""
    return f"{PITCH_CLASS_NAMES[m % 12]}{m // 12 - 1}"


def harm_key_name(tonic: int, mode: int) -> str:
    if tonic > 11:
        tonic = 0
    return f"{PITCH_CLASS_NAMES[tonic]} {'minor' if mode else 'major'}"


class Parser:
    """Framed UART packet parser.

    Packet format (from rtl/uart_tx_wrapper.sv):
      NUM_BYTES bytes, MSB of each byte is a framing bit:
        byte 0:    MSB=1 (start), lower 7 bits = top 7 payload bits
        byte 1..:  MSB=0, lower 7 bits = next 7 payload bits
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
        self._packet_times: deque[float] = deque()
        self._last_rate_log: float = 0.0

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

    def get_packet_stats(self) -> tuple[float, float]:
        """Rolling 1-second stats: (rate_hz, avg_latency_ms)."""
        now = time.monotonic()
        with self._lock:
            cutoff = now - 1.0
            while self._packet_times and self._packet_times[0] < cutoff:
                self._packet_times.popleft()
            n = len(self._packet_times)
            if n < 2:
                return (float(n), 0.0)
            span = self._packet_times[-1] - self._packet_times[0]
            avg_latency_ms = (span / (n - 1)) * 1000.0
            return (float(n), avg_latency_ms)

    def _on_reading(
        self, detected_hz: float | None, corrected_hz: float | None, fields: dict
    ) -> None:
        now = time.monotonic()
        with self._lock:
            self._packet_times.append(now)
            cutoff = now - 1.0
            while self._packet_times and self._packet_times[0] < cutoff:
                self._packet_times.popleft()
            n = len(self._packet_times)
            if n >= 2:
                span = self._packet_times[-1] - self._packet_times[0]
                avg_latency_ms = (span / (n - 1)) * 1000.0
            else:
                avg_latency_ms = 0.0
            should_log = now - self._last_rate_log >= 1.0
            if should_log:
                self._last_rate_log = now
        if should_log:
            print(
                f"[uart_reader] {n} Hz (1s avg), {avg_latency_ms:.2f} ms between packets"
            )
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
                "target_lag": fields["target_lag"],
                "vocode_bands": [v / (1 << 24) for v in fields["vocode_bands"]],
                # Harmony / key telemetry
                "melody_midi": fields["melody_midi"],
                "held_midi": fields["held_midi"],
                "any_note_pressed": bool(fields["any_note_pressed"]),
                "harm1_midi": fields["harm1_midi"],
                "harm2_midi": fields["harm2_midi"],
                "harm_tonic": fields["harm_tonic"],
                "harm_mode": fields["harm_mode"],
                "harm_key_name": harm_key_name(
                    fields["harm_tonic"], fields["harm_mode"]
                ),
                "chord_state": fields["chord_state"],
                "in_scale": bool(fields["in_scale"]),
                "melody_note_name": midi_to_name(fields["melody_midi"]),
                "harm1_note_name": midi_to_name(fields["harm1_midi"]),
                "harm2_note_name": midi_to_name(fields["harm2_midi"]),
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
        results.append((detected, corrected, fields))

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
        target_lag=0,
        melody_midi=0,
        held_midi=0,
        any_note_pressed=0,
        harm1_midi=0,
        harm2_midi=0,
        harm_tonic=0,
        harm_mode=0,
        chord_state=0,
        in_scale=0,
    ) -> list[int]:
        """Build a framed packet from fields."""
        bits = 0
        bits |= (lag & 0x3FF) << 998
        bits |= (int(valid) & 1) << 997
        if bands:
            for j, b in enumerate(bands):
                shift = 996 - j * 27 - 26
                bits |= (b & FIXED_MASK) << shift
        bits |= (mode & 0x7) << 130
        bits |= (vad_active & 1) << 129
        bits |= (vad_voiced & 1) << 128
        bits |= (dac_full & 1) << 127
        bits |= (adc_empty & 1) << 126
        bits |= (config_done & 1) << 125
        bits |= (config_err & 1) << 124
        bits |= (target_lag & 0x3FF) << 114
        bits |= (melody_midi & 0x7F) << 107
        bits |= (held_midi & 0x7F) << 100
        bits |= (any_note_pressed & 1) << 99
        bits |= (harm1_midi & 0x7F) << 92
        bits |= (harm2_midi & 0x7F) << 85
        bits |= (harm_tonic & 0xF) << 81
        bits |= (harm_mode & 1) << 80
        bits |= (chord_state & 0x7) << 77
        bits |= (in_scale & 1) << 76
        # Split into NUM_BYTES groups of 7 bits, MSB-first
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
    d, c, _ = results[-1]
    assert abs(d - 440.37) < 1.0, f"detected_hz wrong: {d}"
    print(f"  detected_hz={d:.2f}  corrected_hz={c:.2f}  OK")

    print("Test 2 — invalid packet (valid=0) emits None hz")
    for b in make_packet(False, 109):
        parser.parse_byte(b)
    d, c, _ = results[-1]
    assert d is None and c is None, "Invalid packet should null out hz"
    print("  None hz  OK")

    print("Test 3 — packet with lag=183 (C4 ~262 Hz)")
    for b in make_packet(True, 183):
        parser.parse_byte(b)
    d, c, _ = results[-1]
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
        target_lag=137,
        melody_midi=69,
        held_midi=72,
        any_note_pressed=1,
        harm1_midi=64,
        harm2_midi=76,
        harm_tonic=9,
        harm_mode=1,
        chord_state=5,
        in_scale=1,
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
    assert f["target_lag"] == 137
    assert f["melody_midi"] == 69
    assert f["held_midi"] == 72
    assert f["any_note_pressed"] == 1
    assert f["harm1_midi"] == 64
    assert f["harm2_midi"] == 76
    assert f["harm_tonic"] == 9
    assert f["harm_mode"] == 1
    assert f["chord_state"] == 5
    assert f["in_scale"] == 1
    for i in range(32):
        assert f["vocode_bands"][i] == test_bands[i], f"band {i} mismatch"
    print(
        f"  harm_key={harm_key_name(f['harm_tonic'], f['harm_mode'])}  "
        f"melody={midi_to_name(f['melody_midi'])}  "
        f"h1={midi_to_name(f['harm1_midi'])}  h2={midi_to_name(f['harm2_midi'])}"
    )
    print("  All fields round-tripped  OK")

    print("All tests passed.")
