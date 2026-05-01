import { useCallback, useEffect, useMemo, useRef } from "react"
import { API_BASE } from "@/config"

export interface PlaybackSnapshot {
  song_id: string
  position_ms: number
  playing: boolean
}

export interface SongPlayback {
  play: (songId: string) => Promise<void>
  stop: () => void
  pause: () => void
  resume: () => Promise<void>
  seek: (ms: number) => void
  getDuration: () => number
  isPaused: () => boolean
  setVocalsVolume: (v: number) => void
  setVocalsBoost: (active: boolean) => void
  getPlayback: () => PlaybackSnapshot | null
  setOnEnded: (cb: (() => void) | null) => void
}

const VOCALS_BOOST_LEVEL = 1.0
const VOCALS_RAMP_MS = 250

export function useSongPlayback(): SongPlayback {
  const instrumentalRef = useRef<HTMLAudioElement | null>(null)
  const vocalsRef = useRef<HTMLAudioElement | null>(null)
  const songIdRef = useRef<string | null>(null)
  const vocalsVolumeRef = useRef<number>(0.3)
  const vocalsBoostRef = useRef<boolean>(false)
  const rampRafRef = useRef<number | null>(null)
  const onEndedRef = useRef<(() => void) | null>(null)

  // Linear ramp on the actual <audio> volume so transitioning between user
  // slider value and boost (1.0) doesn't pop. Recomputes the target each call
  // so an in-flight ramp can be redirected mid-flight.
  const applyVocalsVolume = useCallback((immediate = false) => {
    const vocals = vocalsRef.current
    if (!vocals) return
    const target = vocalsBoostRef.current
      ? VOCALS_BOOST_LEVEL
      : vocalsVolumeRef.current
    if (immediate || VOCALS_RAMP_MS <= 0) {
      vocals.volume = Math.max(0, Math.min(1, target))
      return
    }
    if (rampRafRef.current !== null) {
      window.cancelAnimationFrame(rampRafRef.current)
      rampRafRef.current = null
    }
    const start = vocals.volume
    const t0 = performance.now()
    const tick = (now: number) => {
      const t = Math.min(1, (now - t0) / VOCALS_RAMP_MS)
      const liveTarget = vocalsBoostRef.current
        ? VOCALS_BOOST_LEVEL
        : vocalsVolumeRef.current
      const v = start + (liveTarget - start) * t
      const clamped = Math.max(0, Math.min(1, v))
      const cur = vocalsRef.current
      if (cur) cur.volume = clamped
      if (t < 1) {
        rampRafRef.current = window.requestAnimationFrame(tick)
      } else {
        rampRafRef.current = null
      }
    }
    rampRafRef.current = window.requestAnimationFrame(tick)
  }, [])

  useEffect(() => {
    const instrumental = new Audio()
    const vocals = new Audio()
    instrumental.preload = "auto"
    vocals.preload = "auto"
    vocals.volume = vocalsVolumeRef.current

    const onPlaying = () => {
      vocals.currentTime = instrumental.currentTime
      vocals.play().catch(() => {})
    }
    const onPause = () => {
      vocals.pause()
    }
    const onSeeked = () => {
      vocals.currentTime = instrumental.currentTime
    }
    const onEnded = () => {
      vocals.pause()
      onEndedRef.current?.()
    }

    instrumental.addEventListener("playing", onPlaying)
    instrumental.addEventListener("pause", onPause)
    instrumental.addEventListener("seeked", onSeeked)
    instrumental.addEventListener("ended", onEnded)

    instrumentalRef.current = instrumental
    vocalsRef.current = vocals

    return () => {
      instrumental.removeEventListener("playing", onPlaying)
      instrumental.removeEventListener("pause", onPause)
      instrumental.removeEventListener("seeked", onSeeked)
      instrumental.removeEventListener("ended", onEnded)
      instrumental.pause()
      vocals.pause()
      instrumental.src = ""
      vocals.src = ""
      instrumentalRef.current = null
      vocalsRef.current = null
      if (rampRafRef.current !== null) {
        window.cancelAnimationFrame(rampRafRef.current)
        rampRafRef.current = null
      }
    }
  }, [])

  const play = useCallback(async (songId: string) => {
    const instrumental = instrumentalRef.current
    const vocals = vocalsRef.current
    if (!instrumental || !vocals) return

    instrumental.pause()
    vocals.pause()
    songIdRef.current = songId

    instrumental.src = `${API_BASE}/audio/${songId}/instrumental.mp3`
    vocals.src = `${API_BASE}/audio/${songId}/vocals.mp3`
    instrumental.currentTime = 0
    vocals.currentTime = 0
    // Reset to no-boost so the slider value is the starting point. Phase
    // logic in SingAlongView will call setVocalsBoost(true) for preroll.
    vocalsBoostRef.current = false
    applyVocalsVolume(true)

    try {
      await instrumental.play()
    } catch (err) {
      console.warn("[useSongPlayback] instrumental.play() rejected", err)
    }
  }, [applyVocalsVolume])

  const pause = useCallback(() => {
    instrumentalRef.current?.pause()
  }, [])

  const resume = useCallback(async () => {
    const instrumental = instrumentalRef.current
    if (!instrumental || !instrumental.src) return
    try {
      await instrumental.play()
    } catch (err) {
      console.warn("[useSongPlayback] resume rejected", err)
    }
  }, [])

  const seek = useCallback((ms: number) => {
    const instrumental = instrumentalRef.current
    if (!instrumental) return
    const dur = instrumental.duration
    const clamped = Math.max(0, Math.min(Number.isFinite(dur) ? dur : Infinity, ms / 1000))
    instrumental.currentTime = clamped
  }, [])

  const getDuration = useCallback(() => {
    const d = instrumentalRef.current?.duration
    return Number.isFinite(d) ? (d as number) : 0
  }, [])

  const isPaused = useCallback(() => {
    return instrumentalRef.current?.paused ?? true
  }, [])

  const stop = useCallback(() => {
    const instrumental = instrumentalRef.current
    const vocals = vocalsRef.current
    songIdRef.current = null
    if (rampRafRef.current !== null) {
      window.cancelAnimationFrame(rampRafRef.current)
      rampRafRef.current = null
    }
    vocalsBoostRef.current = false
    if (instrumental) {
      instrumental.pause()
      instrumental.removeAttribute("src")
      instrumental.load()
    }
    if (vocals) {
      vocals.pause()
      vocals.removeAttribute("src")
      vocals.load()
    }
  }, [])

  const setVocalsVolume = useCallback(
    (v: number) => {
      const clamped = Math.max(0, Math.min(1, v))
      vocalsVolumeRef.current = clamped
      // If boost is active, the user's slider doesn't drive output volume.
      // Either way, applyVocalsVolume picks the right target from the refs.
      applyVocalsVolume(true)
    },
    [applyVocalsVolume],
  )

  const setVocalsBoost = useCallback(
    (active: boolean) => {
      if (vocalsBoostRef.current === active) return
      vocalsBoostRef.current = active
      applyVocalsVolume(false)
    },
    [applyVocalsVolume],
  )

  const getPlayback = useCallback((): PlaybackSnapshot | null => {
    const instrumental = instrumentalRef.current
    const songId = songIdRef.current
    if (!instrumental || !songId) return null
    return {
      song_id: songId,
      position_ms: instrumental.currentTime * 1000,
      playing: !instrumental.paused && !instrumental.ended,
    }
  }, [])

  const setOnEnded = useCallback((cb: (() => void) | null) => {
    onEndedRef.current = cb
  }, [])

  return useMemo(
    () => ({
      play,
      stop,
      pause,
      resume,
      seek,
      getDuration,
      isPaused,
      setVocalsVolume,
      setVocalsBoost,
      getPlayback,
      setOnEnded,
    }),
    [
      play,
      stop,
      pause,
      resume,
      seek,
      getDuration,
      isPaused,
      setVocalsVolume,
      setVocalsBoost,
      getPlayback,
      setOnEnded,
    ],
  )
}
