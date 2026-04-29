import asyncio
import json
import os
import statistics
import time
from collections import deque
from contextlib import asynccontextmanager

import mido
import serial
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from midi_bridge import MIDIBridge
from scoring import ScoringSession
from song_manager import SongManager
from uart_parser import UARTParser

SERIAL_PORT = "/dev/cu.usbserial-FTA9O9VB"
BAUD = 31250
WS_INTERVAL = 0.033  # ~30 Hz
PLAYBACK_STALE_S = 0.25

SONGS_DIR = os.path.join(os.path.dirname(__file__), "..", "songs")

uart_reader: UARTParser | None = None
midi_bridge: MIDIBridge | None = None
song_manager: SongManager = SongManager(SONGS_DIR)
scoring_session: ScoringSession | None = None
_connected: set[WebSocket] = set()
_playback_state: dict = {
    "song_id": None,
    "position_ms": None,
    "playing": False,
    "received_at": 0.0,
}


async def _broadcast(message: dict) -> None:
    dead = set()
    data = json.dumps(message)
    for ws in _connected:
        try:
            await ws.send_text(data)
        except Exception:
            dead.add(ws)
    _connected.difference_update(dead)


async def _pitch_loop() -> None:
    global scoring_session

    detected_window: deque[float] = deque(maxlen=5)
    corrected_window: deque[float] = deque(maxlen=5)
    was_playing = False

    while True:
        await asyncio.sleep(WS_INTERVAL)
        if not _connected:
            continue

        reading = uart_reader.get_latest() if uart_reader else None

        fresh = (time.monotonic() - _playback_state["received_at"]) <= PLAYBACK_STALE_S
        playing = bool(_playback_state["playing"]) and fresh
        position_ms = _playback_state["position_ms"] if playing else None
        raw_target = (
            song_manager.get_target_hz(position_ms) if position_ms is not None else None
        )
        target_hz = round(raw_target, 2) if raw_target is not None else None
        lyric = (
            song_manager.get_current_lyric(position_ms)
            if position_ms is not None
            else None
        )
        song_position_ms = round(position_ms) if position_ms is not None else None

        filtered_detected: float | None = None
        filtered_corrected: float | None = None
        vad_voiced_flag = False

        if reading:
            octave_outlier = False
            vad_voiced_flag = bool(reading.get("vad_voiced"))
            if reading.get("vad_active") and vad_voiced_flag:
                detected_hz = reading["detected_hz"]
                corrected_hz = reading["corrected_hz"]
                if detected_hz is not None and detected_window:
                    ref = statistics.median(detected_window)
                    if ref > 0:
                        r = detected_hz / ref
                        # Reject ~2x and ~0.5x glitches. Corrected is downstream
                        # of the same lag, so drop both to keep gaps aligned.
                        if 1.7 <= r <= 2.3 or 0.43 <= r <= 0.59:
                            octave_outlier = True
                if not octave_outlier:
                    if detected_hz is not None:
                        detected_window.append(detected_hz)
                    if corrected_hz is not None:
                        corrected_window.append(corrected_hz)
            else:
                detected_window.clear()
                corrected_window.clear()
            if octave_outlier:
                filtered_detected = None
                filtered_corrected = None
            else:
                filtered_detected = (
                    round(statistics.median(detected_window), 2)
                    if detected_window
                    else None
                )
                filtered_corrected = (
                    round(statistics.median(corrected_window), 2)
                    if corrected_window
                    else None
                )

        # --- scoring ---
        score_fields = {
            "detected_hit": None,
            "detected_near": None,
            "detected_miss": None,
            "target_hz_display": None,
            "score": None,
            "combo": None,
            "best_combo": None,
            "stars": None,
            "song_complete": None,
            "note_completed": None,
        }
        if scoring_session is not None and position_ms is not None:
            state = scoring_session.update(
                position_ms=position_ms,
                detected_hz=filtered_detected,
                target_hz=raw_target,
                vad_voiced=vad_voiced_flag,
            )
            score_fields["target_hz_display"] = (
                round(state.target_hz_display, 2)
                if state.target_hz_display is not None
                else None
            )
            score_fields["score"] = round(state.score, 4)
            score_fields["combo"] = state.combo
            score_fields["best_combo"] = state.best_combo
            score_fields["stars"] = state.stars
            score_fields["song_complete"] = state.complete
            if state.note_completed is not None:
                nr = state.note_completed
                score_fields["note_completed"] = {
                    "lyric": nr.lyric,
                    "pitch_hz": round(nr.pitch_hz, 2),
                    "score": round(nr.score, 4),
                }
            if state.detected_bucket == "hit":
                score_fields["detected_hit"] = filtered_detected
            elif state.detected_bucket == "near":
                score_fields["detected_near"] = filtered_detected
            elif state.detected_bucket == "miss":
                score_fields["detected_miss"] = filtered_detected

        # --- song-complete on stop / natural end ---
        if was_playing and not playing and scoring_session is not None:
            final = scoring_session.finish()
            score_fields["score"] = round(final.score, 4)
            score_fields["combo"] = final.combo
            score_fields["best_combo"] = final.best_combo
            score_fields["stars"] = final.stars
            score_fields["song_complete"] = True
            scoring_session = None
        was_playing = playing

        if reading:
            msg = {
                "detected_hz": filtered_detected,
                "corrected_hz": filtered_corrected,
                "target_hz": target_hz,
                "lyric": lyric,
                "song_position_ms": song_position_ms,
                "timestamp_ms": int(time.monotonic() * 1000),
                "mode": reading["mode"],
                "vad_active": reading["vad_active"],
                "vad_voiced": reading["vad_voiced"],
                "dac_full": reading["dac_full"],
                "adc_empty": reading["adc_empty"],
                "config_done": reading["config_done"],
                "config_err": reading["config_err"],
                "vocode_bands": reading["vocode_bands"],
            }
        else:
            # No packet received yet — emit nulls so the frontend graph keeps ticking
            msg = {
                "detected_hz": None,
                "corrected_hz": None,
                "target_hz": target_hz,
                "lyric": lyric,
                "song_position_ms": song_position_ms,
                "timestamp_ms": int(time.monotonic() * 1000),
                "mode": None,
                "vad_active": None,
                "vad_voiced": None,
                "dac_full": None,
                "adc_empty": None,
                "config_done": None,
                "config_err": None,
                "vocode_bands": None,
            }

        msg.update(score_fields)
        await _broadcast(msg)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global uart_reader, midi_bridge

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD, timeout=1)
        uart_reader = UARTParser(ser)
        uart_reader.start()
        midi_bridge = MIDIBridge(ser)
        midi_bridge.start()
        print(f"[main] serial port {SERIAL_PORT} opened at {BAUD} baud")
    except serial.SerialException as e:
        print(
            f"[main] WARNING: could not open serial port ({e}) — running without UART/MIDI"
        )
        uart_reader = None
        midi_bridge = None

    task = asyncio.create_task(_pitch_loop())

    yield

    task.cancel()
    if midi_bridge:
        midi_bridge.stop()
    if uart_reader:
        uart_reader.stop()


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/audio", StaticFiles(directory=SONGS_DIR), name="audio")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "uart": uart_reader is not None,
        "midi": midi_bridge is not None,
        "ws_clients": len(_connected),
    }


@app.get("/songs")
def list_songs():
    return song_manager.list_songs()


@app.get("/songs/{song_id}/cover")
def song_cover(song_id: str):
    path = song_manager.cover_path(song_id)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Cover not found")
    return FileResponse(path, media_type="image/jpeg")


@app.get("/songs/{song_id}/lyrics")
def song_lyrics(song_id: str):
    path = os.path.join(song_manager.song_dir(song_id), "lyrics.json")
    if not os.path.isfile(path):
        return []
    with open(path) as f:
        return json.load(f)


@app.post("/songs/{song_id}/start")
def start_song(song_id: str):
    global scoring_session
    instrumental = song_manager.instrumental_path(song_id)
    if not os.path.isfile(instrumental):
        raise HTTPException(status_code=404, detail="Song not found")
    song_manager.load(song_id)
    notes = song_manager.get_notes()
    scoring_session = ScoringSession(notes) if notes else None
    return {"ok": True, "song_id": song_id, "note_count": len(notes)}


@app.post("/songs/stop")
def stop_song():
    _playback_state["song_id"] = None
    _playback_state["position_ms"] = None
    _playback_state["playing"] = False
    _playback_state["received_at"] = 0.0
    song_manager.unload()
    return {"ok": True}


class MidiCommand(BaseModel):
    # Raw MIDI bytes, e.g. [0x90, 0x3C, 0x7F] for note-on C4 velocity 127.
    # Exact command types are TBD — this endpoint is the plumbing.
    bytes: list[int]


@app.post("/midi/command")
def midi_command(cmd: MidiCommand):
    if midi_bridge is None:
        return {"ok": False, "error": "MIDI bridge not available"}
    midi_bridge.send_raw(bytes(cmd.bytes))
    return {"ok": True, "sent": cmd.bytes}


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    _connected.add(ws)
    try:
        while True:
            text = await ws.receive_text()
            try:
                msg = json.loads(text)
            except (ValueError, TypeError):
                continue
            if not isinstance(msg, dict):
                continue
            if msg.get("type") == "playback":
                pos = msg.get("position_ms")
                _playback_state["song_id"] = msg.get("song_id")
                _playback_state["position_ms"] = (
                    float(pos) if isinstance(pos, (int, float)) else None
                )
                _playback_state["playing"] = bool(msg.get("playing"))
                _playback_state["received_at"] = time.monotonic()
    except WebSocketDisconnect:
        pass
    finally:
        _connected.discard(ws)
