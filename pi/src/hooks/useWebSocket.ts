import { useEffect, useRef, useState } from "react"

export interface FrequencyPoint {
  ts: number
  hz: number
}

const WINDOW_MS = 10_000 // 10 second rolling window
const THROTTLE_MS = 100  // push to consumers at 10fps

export function useFrequencyData() {
  const [points, setPoints] = useState<FrequencyPoint[]>([])
  const [connected, setConnected] = useState(false)
  const bufRef = useRef<FrequencyPoint[]>([])

  useEffect(() => {
    const url = `ws://${window.location.host}/ws`
    let ws: WebSocket

    function connect() {
      ws = new WebSocket(url)
      ws.onopen = () => setConnected(true)
      ws.onclose = () => {
        setConnected(false)
        setTimeout(connect, 2000) // reconnect on drop
      }
      ws.onmessage = (e) => {
        const point: FrequencyPoint = JSON.parse(e.data as string)
        console.log(`[ws] ${point.hz.toFixed(2)} Hz  (ts=${point.ts})`)
        const cutoff = Date.now() - WINDOW_MS
        bufRef.current = [
          ...bufRef.current.filter((p) => p.ts > cutoff),
          point,
        ]
      }
    }

    connect()
    const timer = setInterval(() => setPoints([...bufRef.current]), THROTTLE_MS)

    return () => {
      ws.close()
      clearInterval(timer)
    }
  }, [])

  return { points, connected }
}
