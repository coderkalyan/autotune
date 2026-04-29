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
  getPlayback: () => PlaybackSnapshot | null
  setOnEnded: (cb: (() => void) | null) => void
}

export function useSongPlayback(): SongPlayback {
  const instrumentalRef = useRef<HTMLAudioElement | null>(null)
  const vocalsRef = useRef<HTMLAudioElement | null>(null)
  const songIdRef = useRef<string | null>(null)
  const vocalsVolumeRef = useRef<number>(0.3)
  const onEndedRef = useRef<(() => void) | null>(null)

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
    vocals.volume = vocalsVolumeRef.current

    try {
      await instrumental.play()
    } catch (err) {
      console.warn("[useSongPlayback] instrumental.play() rejected", err)
    }
  }, [])

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

  const setVocalsVolume = useCallback((v: number) => {
    const clamped = Math.max(0, Math.min(1, v))
    vocalsVolumeRef.current = clamped
    if (vocalsRef.current) vocalsRef.current.volume = clamped
  }, [])

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
      getPlayback,
      setOnEnded,
    ],
  )
}
