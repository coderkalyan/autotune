import threading
import time

import sounddevice as sd
import soundfile as sf


class AudioEngine:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._stream: sd.OutputStream | None = None
        self._data = None          # numpy array (instrumental)
        self._vocals = None        # numpy array (optional vocal stem)
        self._vocals_volume: float = 0.3
        self._samplerate: int = 48000
        self._cursor: int = 0      # current read position in samples
        self._playing = False
        self._start_wall: float = 0.0

    def play(self, wav_path: str, vocals_path: str | None = None, vocals_volume: float = 0.3) -> None:
        self.stop()
        data, samplerate = sf.read(wav_path, dtype="float32", always_2d=True)
        vocals = None
        if vocals_path:
            try:
                vocals, _ = sf.read(vocals_path, dtype="float32", always_2d=True)
            except Exception:
                vocals = None
        with self._lock:
            self._data = data
            self._vocals = vocals
            self._vocals_volume = vocals_volume
            self._samplerate = samplerate
            self._cursor = 0
            self._playing = True
            self._start_wall = time.monotonic()

        stream = sd.OutputStream(
            samplerate=samplerate,
            channels=data.shape[1],
            dtype="float32",
            callback=self._callback,
            finished_callback=self._on_finished,
        )
        self._stream = stream
        stream.start()

    def _callback(self, outdata, frames, time_info, status):
        with self._lock:
            if self._data is None or not self._playing:
                outdata[:] = 0
                return
            remaining = len(self._data) - self._cursor
            if remaining <= 0:
                outdata[:] = 0
                return
            chunk = min(frames, remaining)
            outdata[:chunk] = self._data[self._cursor : self._cursor + chunk]
            if self._vocals is not None:
                vlen = len(self._vocals)
                vchunk = min(chunk, max(0, vlen - self._cursor))
                if vchunk > 0:
                    outdata[:vchunk] += self._vocals[self._cursor : self._cursor + vchunk] * self._vocals_volume
            if chunk < frames:
                outdata[chunk:] = 0
            self._cursor += chunk

    def _on_finished(self):
        with self._lock:
            self._playing = False

    def stop(self) -> None:
        with self._lock:
            self._playing = False
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception:
                pass
            self._stream = None
        with self._lock:
            self._data = None
            self._vocals = None
            self._cursor = 0

    def get_position_ms(self) -> float:
        with self._lock:
            if not self._playing or self._samplerate == 0:
                return 0.0
            return (self._cursor / self._samplerate) * 1000.0

    def set_vocals_volume(self, volume: float) -> None:
        with self._lock:
            self._vocals_volume = max(0.0, min(1.0, volume))

    @property
    def is_playing(self) -> bool:
        with self._lock:
            return self._playing
