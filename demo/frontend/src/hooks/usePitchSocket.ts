import { useCallback, useEffect, useRef, useState } from "react"
import { PITCH_WINDOW_SIZE, WS_URL } from "@/config"
import type { PitchReading } from "@/types"
import type { PlaybackSnapshot } from "./useSongPlayback"

// Chart updates at 10Hz — every 3rd message from the 30Hz stream.
// `latest` still updates at full rate for the tuner strip.
const CHART_UPDATE_EVERY = 3
const PLAYBACK_SEND_INTERVAL_MS = 33

export function usePitchSocket(
  url: string = WS_URL,
  getPlayback?: () => PlaybackSnapshot | null,
) {
  const [readings, setReadings] = useState<PitchReading[]>([])
  const [latest, setLatest] = useState<PitchReading | null>(null)
  const [connected, setConnected] = useState(false)

  const wsRef = useRef<WebSocket | null>(null)
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const playbackTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const unmountedRef = useRef(false)
  // Buffer accumulates between chart updates; flushed every CHART_UPDATE_EVERY messages
  const bufferRef = useRef<PitchReading[]>([])
  const msgCountRef = useRef(0)
  const lastGoodDetectedRef = useRef<number | null>(null)
  const lastGoodCorrectedRef = useRef<number | null>(null)
  const getPlaybackRef = useRef(getPlayback)
  getPlaybackRef.current = getPlayback

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
      if (playbackTimerRef.current === null) {
        playbackTimerRef.current = setInterval(() => {
          const sock = wsRef.current
          if (!sock || sock.readyState !== WebSocket.OPEN) return
          const snap = getPlaybackRef.current?.()
          if (!snap) return
          sock.send(JSON.stringify({ type: "playback", ...snap }))
        }, PLAYBACK_SEND_INTERVAL_MS)
      }
    }

    ws.onmessage = (event: MessageEvent) => {
      try {
        const reading = JSON.parse(event.data as string) as PitchReading

        const isVoiced = reading.vad_active === true && reading.vad_voiced === true
        // Backend may null detected_hz on octave outliers even while VAD is
        // voiced; the null-check below routes those frames into the held
        // (dashed-bridge) branch automatically.
        if (isVoiced && reading.detected_hz !== null) {
          lastGoodDetectedRef.current = reading.detected_hz
          lastGoodCorrectedRef.current = reading.corrected_hz
          reading.detected_held = null
          reading.corrected_held = null
        } else {
          reading.detected_held = lastGoodDetectedRef.current
          reading.corrected_held = lastGoodCorrectedRef.current
          reading.detected_hz = null
          reading.corrected_hz = null
        }

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
      if (playbackTimerRef.current !== null) {
        clearInterval(playbackTimerRef.current)
        playbackTimerRef.current = null
      }
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
      if (playbackTimerRef.current !== null) {
        clearInterval(playbackTimerRef.current)
        playbackTimerRef.current = null
      }
      wsRef.current?.close()
    }
  }, [connect])

  const sendMessage = useCallback((msg: object) => {
    const sock = wsRef.current
    if (!sock || sock.readyState !== WebSocket.OPEN) return
    sock.send(JSON.stringify(msg))
  }, [])

  return { readings, latest, connected, sendMessage }
}
