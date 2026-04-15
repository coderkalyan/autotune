import platform
import threading

import mido
import mido.backends.rtmidi
import serial

VIRTUAL_PORT_NAME = "To_FPGA"


class MIDIBridge:
    """Forwards MIDI keyboard input to the FPGA over serial, and allows the
    backend to inject MIDI commands programmatically (e.g. from web app buttons).

    On macOS: uses CoreMIDI (mido default).
    On Linux/Pi: explicitly selects the rtmidi backend.
    """

    def __init__(self, ser: serial.Serial):
        self._ser = ser
        self._thread: threading.Thread | None = None
        self._port: mido.ports.BaseInput | None = None
        self._stop_event = threading.Event()

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

    def send_raw(self, data: bytes) -> None:
        """Write raw bytes to the FPGA serial port. Used by REST endpoints."""
        self._ser.write(data)

    def send_midi(self, msg: mido.Message) -> None:
        """Convenience wrapper — serialize a mido Message and send it."""
        self.send_raw(msg.bytes())

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
                self._ser.write(msg.bytes())
                print(f"[midi_bridge] → FPGA: {msg}")

        except Exception as e:
            print(f"[midi_bridge] error: {e}")
        finally:
            print("[midi_bridge] stopped")
