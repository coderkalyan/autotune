import { SerialPort } from "serialport"

async function detectPort(): Promise<string> {
  if (process.env.SERIAL_PORT) return process.env.SERIAL_PORT
  const ports = await SerialPort.list()
  // Mac: /dev/tty.usbserial-*   Pi: /dev/ttyUSB*
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

export async function startSerial(onData: Listener): Promise<() => void> {
  const portPath = await detectPort()
  console.log(`[serial] opening ${portPath} @ 31250 baud`)

  const port = new SerialPort({ path: portPath, baudRate: 31250 })
  let buf: number[] = []

  port.on("data", (chunk: Buffer) => {
    for (const byte of chunk) {
      if (buf.length === 0) {
        // Byte 0 must be 0x00-0x07 (invalid) or 0x80-0x87 (valid).
        // Packet bits[31:27] = {valid, 0, 0, 0, period[26]} so the top 5
        // bits are always 10000 or 00000 — anything else means we're mid-packet.
        const hi = byte & 0xf8
        if (hi !== 0x00 && hi !== 0x80) continue // out-of-sync, skip
      }
      buf.push(byte)
      if (buf.length === 4) {
        const raw = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3]
        buf = []
        const valid = (raw >>> 31) & 1
        if (!valid) continue
        const period_q = raw & 0x07ffffff // 27 LSBs (Q11.16 period in samples)
        if (period_q === 0) continue
        const hz = 48000 / (period_q / 65536)
        onData({ ts: Date.now(), hz })
      }
    }
  })

  port.on("error", (err: Error) =>
    console.error("[serial] error:", err.message)
  )

  return () => port.close()
}
