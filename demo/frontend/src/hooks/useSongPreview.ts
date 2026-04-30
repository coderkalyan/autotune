import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { API_BASE } from "@/config"
import type { SongEntry } from "@/types"

const PREVIEW_MS = 5000
const INSTRUMENTAL_VOLUME = 0.5
const VOCALS_VOLUME = 1.0

export interface SongPreview {
  previewingId: string | null
  toggle: (song: SongEntry) => void
  stop: () => void
}

export function useSongPreview(): SongPreview {
  const instrumentalRef = useRef<HTMLAudioElement | null>(null)
  const vocalsRef = useRef<HTMLAudioElement | null>(null)
  const timerRef = useRef<number | null>(null)
  const previewIdRef = useRef<string | null>(null)
  const [previewingId, setPreviewingId] = useState<string | null>(null)

  const stop = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }
    instrumentalRef.current?.pause()
    vocalsRef.current?.pause()
    previewIdRef.current = null
    setPreviewingId(null)
  }, [])

  useEffect(() => {
    const instrumental = new Audio()
    const vocals = new Audio()
    instrumental.preload = "auto"
    vocals.preload = "auto"
    instrumentalRef.current = instrumental
    vocalsRef.current = vocals

    return () => {
      if (timerRef.current !== null) {
        window.clearTimeout(timerRef.current)
        timerRef.current = null
      }
      instrumental.pause()
      vocals.pause()
      instrumental.src = ""
      vocals.src = ""
      instrumentalRef.current = null
      vocalsRef.current = null
    }
  }, [])

  const toggle = useCallback(
    (song: SongEntry) => {
      const instrumental = instrumentalRef.current
      const vocals = vocalsRef.current
      if (!instrumental || !vocals) return

      if (previewIdRef.current === song.id) {
        stop()
        return
      }

      stop()

      instrumental.src = `${API_BASE}/audio/${song.id}/instrumental.mp3`
      vocals.src = `${API_BASE}/audio/${song.id}/vocals.mp3`
      const startSec = song.grade_start_ms / 1000
      instrumental.currentTime = startSec
      vocals.currentTime = startSec
      instrumental.volume = INSTRUMENTAL_VOLUME
      vocals.volume = VOCALS_VOLUME

      previewIdRef.current = song.id
      setPreviewingId(song.id)

      Promise.all([instrumental.play(), vocals.play()]).catch((err) => {
        console.warn("[useSongPreview] play rejected", err)
      })

      timerRef.current = window.setTimeout(() => {
        timerRef.current = null
        stop()
      }, PREVIEW_MS)
    },
    [stop],
  )

  return useMemo(() => ({ previewingId, toggle, stop }), [previewingId, toggle, stop])
}
