import platform
import threading

import mido
import mido.backends.rtmidi
import serial

VIRTUAL_PORT_NAME = "To_FPGA"


class MIDIBridge:
    """Forwards MIDI keyboard input to the FPGA over serial, and allows the
    backend to inject MIDI commands programmatically (e.g. from web app buttons).

    Also tracks which channel-0 piano notes are currently held so the WebSocket
    layer can surface live keyboard state to the frontend (Synth visualization).

    On macOS: uses CoreMIDI (mido default).
    On Linux/Pi: explicitly selects the rtmidi backend.
    """

    def __init__(self, ser: serial.Serial):
        self._ser = ser
        self._thread: threading.Thread | None = None
        self._port: mido.ports.BaseInput | None = None
        self._stop_event = threading.Event()
        self._lock = threading.Lock()
        self._active_notes: set[int] = set()

    def start(self) -> None:
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._run, daemon=True, name="midi-bridge"
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._port:
            try:
                self._port.close()
            except Exception:
                pass
        if self._thread:
            self._thread.join(timeout=2.0)
        with self._lock:
            self._active_notes.clear()

    def send_raw(self, data: bytes) -> None:
        """Write raw bytes to the FPGA serial port. Used by REST endpoints."""
        self._ser.write(data)

    def send_midi(self, msg: mido.Message) -> None:
        """Convenience wrapper — serialize a mido Message and send it."""
        self.send_raw(msg.bytes())

    def send_note(
        self,
        note: int,
        on: bool,
        velocity: int = 100,
        channel: int = 0,
    ) -> None:
        """Build a Note On/Off message, update active-note tracking, and forward to FPGA.

        Used for frontend-driven keys so they appear in get_active_notes() and
        therefore in the WebSocket telemetry's midi_notes field.
        """
        msg = mido.Message(
            "note_on" if on else "note_off",
            note=note,
            velocity=velocity if on else 0,
            channel=channel,
        )
        self._track(msg)
        self._ser.write(msg.bytes())

    def get_active_notes(self) -> list[int]:
        with self._lock:
            return sorted(self._active_notes)

    def _track(self, msg: mido.Message) -> None:
        # Channel 9 is reserved for the mode-select pads (see midi_receiver.sv);
        # only piano-channel notes belong on the visualization.
        if getattr(msg, "channel", None) != 0:
            return
        if msg.type == "note_on" and msg.velocity > 0:
            with self._lock:
                self._active_notes.add(msg.note)
        elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
            with self._lock:
                self._active_notes.discard(msg.note)

    def _run(self) -> None:
        try:
            if platform.system() == "Linux":
                backend = mido.Backend("mido.backends.rtmidi")
                self._port = backend.open_input(VIRTUAL_PORT_NAME, virtual=True)
            else:
                self._port = mido.open_input(VIRTUAL_PORT_NAME, virtual=True)

            print(f"[midi_bridge] virtual port '{VIRTUAL_PORT_NAME}' open")

            for msg in self._port:
                if self._stop_event.is_set():
                    break
                # Skip MIDI clock bytes — they fire at 24 ppqn and flood the port
                if msg.bytes() == [0xF8]:
                    continue
                self._track(msg)
                self._ser.write(msg.bytes())
                print(f"[midi_bridge] → FPGA: {msg}")

        except Exception as e:
            print(f"[midi_bridge] error: {e}")
        finally:
            print("[midi_bridge] stopped")
