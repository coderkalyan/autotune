export const WS_URL = (import.meta.env.VITE_WS_URL as string | undefined) ?? "ws://localhost:8000/ws"
export const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? "http://localhost:8000"
export const PITCH_WINDOW_SIZE = 600 // 20s × 30Hz
export const PITCH_MIN_HZ = 60
export const PITCH_MAX_HZ = 600
