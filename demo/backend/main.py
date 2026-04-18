import asyncio
import json
import os
import time
from contextlib import asynccontextmanager

import mido
import serial
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

from audio_engine import AudioEngine
from midi_bridge import MIDIBridge
from song_manager import SongManager
from uart_parser import UARTParser

SERIAL_PORT = "/dev/ttyUSB0"
BAUD = 31250
WS_INTERVAL = 0.033  # ~30 Hz

SONGS_DIR = os.path.join(os.path.dirname(__file__), "..", "songs")

uart_reader: UARTParser | None = None
midi_bridge: MIDIBridge | None = None
song_manager: SongManager = SongManager(SONGS_DIR)
audio_engine: AudioEngine = AudioEngine()
_connected: set[WebSocket] = set()


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
    while True:
        await asyncio.sleep(WS_INTERVAL)
        if not _connected:
            continue

        reading = uart_reader.get_latest() if uart_reader else None

        position_ms = (
            audio_engine.get_position_ms() if audio_engine.is_playing else None
        )
        raw_target = (
            song_manager.get_target_hz(position_ms) if position_ms is not None else None
        )
        target_hz = round(raw_target, 2) if raw_target is not None else None

        if reading:
            msg = {
                "detected_hz": round(reading["detected_hz"], 2)
                if reading["detected_hz"] is not None
                else None,
                "corrected_hz": round(reading["corrected_hz"], 2)
                if reading["corrected_hz"] is not None
                else None,
                "target_hz": target_hz,
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


@app.post("/songs/{song_id}/play")
def play_song(song_id: str):
    instrumental = song_manager.instrumental_path(song_id)
    if not os.path.isfile(instrumental):
        raise HTTPException(status_code=404, detail="Song not found")
    song_manager.load(song_id)
    audio_engine.play(instrumental)
    return {"ok": True, "playing": song_id}


@app.post("/songs/stop")
def stop_song():
    audio_engine.stop()
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
            await ws.receive_text()  # keep connection alive; ignore incoming
    except WebSocketDisconnect:
        pass
    finally:
        _connected.discard(ws)
