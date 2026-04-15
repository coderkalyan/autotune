# Vocoder / Autotune FPGA Demo — Project Overview

## What This Is

A live demo app running on a Raspberry Pi that visualizes and drives an FPGA-based autotune and vocoder system. The FPGA handles all audio DSP (pitch detection via autocorrelation, pitch correction, and audio output). The Pi handles song management, UART communication with the FPGA, audio playback of backing tracks, and serving a React frontend for visualization.

## Hardware Setup

- **FPGA**: Performs autocorrelation-based pitch detection, nearest-note correction via LUT, and outputs corrected audio to speaker
- **Microphone**: Plugged directly into the FPGA
- **Raspberry Pi**: Running ROS, connected to FPGA via UART on `/dev/ttyUSB0` at baud rate `31250`
- **Display**: Monitor connected to Pi, running the React frontend locally

## Modes

### Autotune — Sing-Along Mode
The user sings along to a pre-processed song. The frontend shows a scrolling pitch graph with three lines:
- **Detected pitch**: raw frequency from FPGA UART, converted from 10-bit pitch period (`f = 48000 / pitch_period`)
- **Corrected pitch**: nearest-note estimate computed on the Pi using the same LUT logic as the FPGA
- **Target pitch**: precomputed lead vocal pitch from the song's stem, scraped offline

### Autotune — Free Mode
Same as sing-along but no song is playing and no target vocal line is shown. Two lines on the graph:
- Detected pitch
- Corrected pitch

### Vocoder Mode
TBD — will display different visualizations. Not in scope for initial build.

## Architecture

```
Mic → FPGA → UART (/dev/ttyUSB0, 31250 baud)
               ↓
        Python Backend (FastAPI)
        - UART reader thread: parses 10-bit pitch period, computes Hz + corrected note
        - WebSocket server: streams pitch data to frontend
        - Audio engine: plays backing track (and optionally vocal stem)
        - Song manager: tracks selected song, playback position, serves precomputed pitch track
               ↓
        React Frontend (Vite)
        - WebSocket client
        - Scrolling real-time pitch graph (uplot)
        - Song selection UI
```

All communication between backend and frontend is over WebSocket on localhost. The frontend is served by Vite on the Pi and displayed on the connected monitor.

## WebSocket Message Format

The backend samples incoming UART data and pushes messages at a controlled rate:

```json
{
  "detected_hz": 243.2,
  "corrected_hz": 246.9,
  "target_hz": 261.6,
  "timestamp_ms": 4823
}
```

`target_hz` is omitted or null in Free Mode.

## UART Protocol

- **Connection**: `/dev/ttyUSB0`, baud `31250`
- **Details**: Take a look at ../rtl/uart_tx_wrapper.sv for the UART protocol details
- **Frequency conversion**: `f = 48000 / pitch_period`
- **Sanity check**: clamp to 80–1100 Hz (typical vocal range); values outside this range are treated as unvoiced/silence

## Nearest-Note LUT (Pi-side)

The Pi re-implements the same nearest-note lookup the FPGA uses to estimate the corrected pitch. Input is frequency in Hz, output is the frequency of the nearest equal-temperament note. This is used for the corrected pitch line on the graph and does not require any data from the FPGA beyond the raw pitch period.

## Pitch Graph

- **X axis**: rolling time window (approximately 5 seconds of history)
- **Lines**: detected (raw), corrected (LUT-snapped), target (vocal stem, sing-along only)
- **Library**: Will start by trying shadcn/ui with recharts. If that reaches limits, then we can change to uPlot or something else webGL based. 

## Song Pipeline (Offline, Pre-Demo)

Songs are preprocessed ahead of time and stored on the Pi. Steps:

1. Download audio (YouTube or other source, 320kbps+ preferred)
2. Run stem splitting with **Demucs** to isolate lead vocals from everything else
3. Run pitch detection on the vocal stem using **librosa.pyin** to produce a timestamped pitch track (stored as a numpy array or CSV: `[timestamp_ms, frequency_hz]`)
4. Store stems and pitch track alongside the original in a structured songs directory

During the demo, the Pi plays the instrumental (and optionally the vocal stem) and scrubs through the precomputed pitch track in sync with playback position.

## Repo Structure (Planned)

```
/
├── backend/
│   ├── main.py              # FastAPI app, WebSocket server
│   ├── uart_reader.py       # UART parsing thread
│   ├── pitch_utils.py       # Hz conversion, nearest-note LUT
│   ├── audio_engine.py      # Backing track playback
│   └── song_manager.py      # Song selection, pitch track scrubbing
├── frontend/
│   └── ...                  # React + Vite app
├── songs/
│   └── <song_name>/
│       ├── instrumental.wav
│       ├── vocals.wav
│       └── pitch_track.csv
├── scripts/
│   └── preprocess_song.py   # Demucs + pyin pipeline
└── CLAUDE.md
```

## Build Order

1. UART parser + pitch utilities (Hz conversion, nearest-note LUT)
2. FastAPI backend with WebSocket server, sampling UART data at controlled rate
3. Song preprocessing script (Demucs + pyin)
4. React frontend with scrolling pitch graph
5. Song manager + audio playback integration
6. Vocoder mode (TBD)