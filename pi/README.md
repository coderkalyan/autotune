# Autotune Demo — Pi Web App

Live pitch visualization for the FPGA autotune project. Receives 32-bit note period packets from the FPGA via UART, converts them to Hz, and graphs them in real time.

## Running with real hardware

```bash
pnpm dev
```

Auto-detects the USB serial port (`/dev/tty.usbserial-*` on Mac, `/dev/ttyUSB0` on Pi). Override with `SERIAL_PORT=`:

```bash
SERIAL_PORT=/dev/tty.usbserial-XXXXX pnpm dev
```

## Running in mock mode (no FPGA)

Requires three terminals. Run them in order.

**Terminal 1 — virtual serial port pair (keep open):**
```bash
socat -d -d pty,raw,echo=0,link=/tmp/fpga_tx pty,raw,echo=0,link=/tmp/fpga_rx
```

**Terminal 2 — web app (from `pi/` directory):**
```bash
SERIAL_PORT=/tmp/fpga_rx USE_FS=1 pnpm dev
```

**Terminal 3 — mock FPGA data (from `pi/` directory):**
```bash
PORT=/tmp/fpga_tx python3 mock_serial.py
```

Open [http://localhost:5173](http://localhost:5173) in your browser.

## Production (Raspberry Pi)

```bash
pnpm build
SERIAL_PORT=/dev/ttyUSB0 node dist/server/index.js
```

Open [http://localhost:3001](http://localhost:3001) in Chromium.

## Packet format

4 bytes per packet. MSB of each byte is a sync flag:

```
Chunk 1: 1VDDDDDD   MSB=1 marks start of packet; V=valid; D=period[26:21]
Chunk 2: 0DDDDDDD   period[20:14]
Chunk 3: 0DDDDDDD   period[13:7]
Chunk 4: 0DDDDDDD   period[6:0]
```

The 27-bit Q11.16 period encodes samples per cycle at 48 kHz:
`frequency = 48000 / (period_q / 65536)`
