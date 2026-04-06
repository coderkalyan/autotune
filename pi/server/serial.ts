import { createReadStream } from "fs"
import { SerialPort } from "serialport"

// Shared packet parser — call once per incoming byte.
//
// Protocol (4 bytes per packet, MSB used for framing):
//   Chunk 1: 1VDDDDDD  — MSB=1 marks start, V=valid, 6 MSBs of Q11.16 period
//   Chunk 2: 0DDDDDDD  — 7 more bits of period
//   Chunk 3: 0DDDDDDD  — 7 more bits of period
//   Chunk 4: 0DDDDDDD  — 7 LSBs of period  (total: 6+7+7+7 = 27 bits)
//
// Sync: scan for MSB=1 to find chunk 1; if MSB=1 arrives mid-packet, resync.
function makeParser(onData: Listener) {
  let buf: number[] = []
  return (byte: number) => {
    const isStart = (byte & 0x80) !== 0
    if (buf.length === 0) {
      if (!isStart) return // waiting for chunk 1 — skip continuation bytes
      buf.push(byte)
    } else {
      if (isStart) { buf = [byte]; return } // unexpected start — resync
      buf.push(byte)
      if (buf.length === 4) {
        const valid = (buf[0] >> 6) & 1
        if (valid) {
          const period_q =
            ((buf[0] & 0x3f) << 21) |
            ((buf[1] & 0x7f) << 14) |
            ((buf[2] & 0x7f) << 7) |
             (buf[3] & 0x7f)
          if (period_q > 0)
            onData({ ts: Date.now(), hz: 48000 / (period_q / 65536) })
        }
        buf = []
      }
    }
  }
}

async function detectPort(): Promise<string> {
  if (process.env.SERIAL_PORT) return process.env.SERIAL_PORT
  const ports = await SerialPort.list()
  const match = ports.find(
    (p) => p.path.includes("usbserial") || p.path.includes("ttyUSB")
  )
  if (match) return match.path
  throw new Error(
    "No serial port found. Set SERIAL_PORT env var or check connection."
  )
}

export interface FrequencyPoint {
  ts: number // Date.now()
  hz: number
}

type Listener = (point: FrequencyPoint) => void

// USE_FS=1: read from a plain file/pipe (mock mode — no baud rate config, no native bindings)
function startFsReader(portPath: string, onData: Listener): () => void {
  console.log(`[serial] reading ${portPath} as raw stream (mock/pipe mode)`)
  const parse = makeParser(onData)
  const stream = createReadStream(portPath)
  stream.on("data", (chunk: Buffer) => { for (const b of chunk) parse(b) })
  stream.on("error", (err) => console.error("[serial] fs error:", err.message))
  return () => stream.destroy()
}

// Default: open a real serial port via serialport (real FPGA hardware)
async function startSerialPort(portPath: string, onData: Listener): Promise<() => void> {
  const baudRate = Number(process.env.BAUD_RATE ?? 31250)
  console.log(`[serial] opening ${portPath} @ ${baudRate} baud`)
  const parse = makeParser(onData)
  const port = new SerialPort({ path: portPath, baudRate })
  port.on("data", (chunk: Buffer) => { for (const b of chunk) parse(b) })
  port.on("error", (err: Error) => console.error("[serial] error:", err.message))
  return () => port.close()
}

export async function startSerial(onData: Listener): Promise<() => void> {
  const portPath = await detectPort()
  if (process.env.USE_FS) return startFsReader(portPath, onData)
  return startSerialPort(portPath, onData)
}
