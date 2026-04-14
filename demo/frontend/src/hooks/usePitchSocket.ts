import { useCallback, useEffect, useRef, useState } from "react"
import { PITCH_WINDOW_SIZE, WS_URL } from "@/config"
import type { PitchReading } from "@/types"

// Chart updates at 10Hz — every 3rd message from the 30Hz stream.
// `latest` still updates at full rate for the tuner strip.
const CHART_UPDATE_EVERY = 3

export function usePitchSocket(url: string = WS_URL) {
  const [readings, setReadings] = useState<PitchReading[]>([])
  const [latest, setLatest] = useState<PitchReading | null>(null)
  const [connected, setConnected] = useState(false)

  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const unmountedRef = useRef(false)
  // Buffer accumulates between chart updates; flushed every CHART_UPDATE_EVERY messages
  const bufferRef = useRef<PitchReading[]>([])
  const msgCountRef = useRef(0)

  const connect = useCallback(() => {
    if (unmountedRef.current) return

    const ws = new WebSocket(url)
    wsRef.current = ws

    ws.onopen = () => {
      if (unmountedRef.current) {
        ws.close()
        return
      }
      setConnected(true)
    }

    ws.onmessage = (event: MessageEvent) => {
      try {
        const reading = JSON.parse(event.data as string) as PitchReading

        // Always update tuner strip at full rate
        setLatest(reading)

        bufferRef.current.push(reading)
        msgCountRef.current++

        if (msgCountRef.current % CHART_UPDATE_EVERY === 0) {
          const incoming = bufferRef.current
          bufferRef.current = []
          setReadings((prev) => {
            const combined = [...prev, ...incoming]
            return combined.length > PITCH_WINDOW_SIZE
              ? combined.slice(combined.length - PITCH_WINDOW_SIZE)
              : combined
          })
        }
      } catch {
        // ignore malformed messages
      }
    }

    ws.onclose = () => {
      setConnected(false)
      if (!unmountedRef.current) {
        reconnectTimerRef.current = setTimeout(connect, 2000)
      }
    }

    ws.onerror = () => {
      ws.close()
    }
  }, [url])

  useEffect(() => {
    unmountedRef.current = false
    connect()

    return () => {
      unmountedRef.current = true
      if (reconnectTimerRef.current !== null) {
        clearTimeout(reconnectTimerRef.current)
      }
      wsRef.current?.close()
    }
  }, [connect])

  return { readings, latest, connected }
}
