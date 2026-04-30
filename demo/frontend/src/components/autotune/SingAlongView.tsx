import { useCallback, useEffect, useRef, useState } from "react"
import { Pause, Play, RotateCcw, Square } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { KaraokeLyrics } from "@/components/autotune/KaraokeLyrics"
import { PulsingBorder } from "@/components/autotune/PulsingBorder"
import { ResultsScreen } from "@/components/autotune/ResultsScreen"
import { StatusRow } from "@/components/autotune/StatusRow"
import { API_BASE } from "@/config"
import type { SongPlayback } from "@/hooks/useSongPlayback"
import { useSongPreview } from "@/hooks/useSongPreview"
import type { LyricLine, NoteCompleted, PitchReading, SongEntry } from "@/types"

interface Props {
  readings: PitchReading[]
  latest?: PitchReading | null
  playback: SongPlayback
}

interface ResultsSnapshot {
  stars: number | null
  score: number | null
  bestCombo: number | null
  songTitle?: string
  notes: NoteCompleted[]
}

function formatTime(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) ms = 0
  const total = Math.floor(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${m}:${s.toString().padStart(2, "0")}`
}

export function SingAlongView({ latest, playback }: Props) {
  const [songs, setSongs] = useState<SongEntry[]>([])
  const [activeSong, setActiveSong] = useState<SongEntry | null>(null)
  const [loading, setLoading] = useState(true)
  const [lyrics, setLyrics] = useState<LyricLine[]>([])
  const [vocalsVolume, setVocalsVolume] = useState(30)
  const [results, setResults] = useState<ResultsSnapshot | null>(null)
  const [positionMs, setPositionMs] = useState(0)
  const [durationMs, setDurationMs] = useState(0)
  const [paused, setPaused] = useState(false)
  const [scrubValue, setScrubValue] = useState<number | null>(null)
  const [noteHistory, setNoteHistory] = useState<NoteCompleted[]>([])
  const lastAppendedNoteRef = useRef<NoteCompleted | null>(null)
  const preview = useSongPreview()

  const handleVolumeChange = useCallback(
    (value: number[]) => {
      const v = value[0]
      setVocalsVolume(v)
      playback.setVocalsVolume(v / 100)
    },
    [playback],
  )

  useEffect(() => {
    fetch(`${API_BASE}/songs`)
      .then((r) => r.json())
      .then((data) => setSongs(data))
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [])

  async function handleSelect(song: SongEntry) {
    preview.stop()
    const [, lyricsData] = await Promise.all([
      fetch(`${API_BASE}/songs/${song.id}/start`, { method: "POST" }),
      fetch(`${API_BASE}/songs/${song.id}/lyrics`)
        .then((r) => r.json())
        .catch(() => []),
    ])
    setLyrics(lyricsData)
    setActiveSong(song)
    setResults(null)
    setPositionMs(0)
    setDurationMs(0)
    setScrubValue(null)
    setPaused(false)
    setNoteHistory([])
    lastAppendedNoteRef.current = null
    playback.setVocalsVolume(vocalsVolume / 100)
    await playback.play(song.id)
  }

  async function handleStop() {
    playback.stop()
    await fetch(`${API_BASE}/songs/stop`, { method: "POST" })
    setActiveSong(null)
    setLyrics([])
    setResults(null)
    setPositionMs(0)
    setDurationMs(0)
    setScrubValue(null)
    setPaused(false)
    setNoteHistory([])
    lastAppendedNoteRef.current = null
  }

  // Append every fresh note_completed event into the per-note history so
  // the results modal can show a per-word breakdown at song end.
  useEffect(() => {
    const nc = latest?.note_completed
    if (!nc) return
    if (nc === lastAppendedNoteRef.current) return
    lastAppendedNoteRef.current = nc
    setNoteHistory((prev) => [...prev, nc])
  }, [latest?.note_completed])

  // Snapshot results so the dialog stays open after the backend tears down
  // the scoring session.
  useEffect(() => {
    if (!latest || !activeSong) return
    if (latest.song_complete && results === null) {
      setResults({
        stars: latest.stars ?? 0,
        score: latest.score ?? 0,
        bestCombo: latest.best_combo ?? 0,
        songTitle: activeSong.title,
        notes: noteHistory,
      })
    }
  }, [latest, activeSong, results, noteHistory])

  // Stop audio when this view unmounts (mode switch or back navigation)
  useEffect(() => {
    return () => {
      if (activeSong) {
        playback.stop()
        fetch(`${API_BASE}/songs/stop`, { method: "POST" }).catch(() => {})
      }
    }
  }, [activeSong, playback])

  // Poll position/duration/paused state from the audio element while a song
  // is active, so the scrubber tracks playback. Skipped while the user is
  // actively dragging the scrubber.
  useEffect(() => {
    if (!activeSong) return
    const tick = () => {
      const snap = playback.getPlayback()
      if (snap && scrubValue === null) {
        setPositionMs(snap.position_ms)
      }
      const dur = playback.getDuration() * 1000
      if (dur > 0) setDurationMs(dur)
      setPaused(playback.isPaused())
    }
    tick()
    const id = window.setInterval(tick, 100)
    return () => window.clearInterval(id)
  }, [activeSong, playback, scrubValue])

  const handleTogglePlay = useCallback(() => {
    if (playback.isPaused()) {
      playback.resume()
    } else {
      playback.pause()
    }
    setPaused(playback.isPaused())
  }, [playback])

  const handleScrubChange = useCallback((v: number[]) => {
    setScrubValue(v[0])
  }, [])

  const seekTo = useCallback(
    async (ms: number) => {
      const clamped = Math.max(0, ms)
      try {
        await fetch(
          `${API_BASE}/songs/seek?position_ms=${encodeURIComponent(clamped)}`,
          { method: "POST" },
        )
      } catch (err) {
        console.warn("[SingAlongView] /songs/seek failed", err)
      }
      playback.seek(clamped)
      setPositionMs(clamped)
    },
    [playback],
  )

  const handleScrubCommit = useCallback(
    async (v: number[]) => {
      await seekTo(v[0])
      setScrubValue(null)
    },
    [seekTo],
  )

  const handleBack10 = useCallback(() => {
    const snap = playback.getPlayback()
    const cur = snap?.position_ms ?? positionMs
    seekTo(cur - 10_000)
  }, [playback, positionMs, seekTo])

  if (activeSong) {
    return (
      <div className="relative flex size-full flex-col">
        <PulsingBorder quality={latest?.frame_quality ?? null} />

        {/* Now-playing strip */}
        <div className="relative z-10 flex shrink-0 items-center gap-3 border-b border-border px-4 py-2">
          <img
            src={`${API_BASE}${activeSong.album_art_url}`}
            alt={activeSong.title}
            className="h-10 w-10 rounded object-cover"
          />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold leading-tight">
              {activeSong.title}
            </p>
            <p className="truncate text-xs text-muted-foreground">
              {activeSong.artist}
            </p>
          </div>
          <div className="flex min-w-0 flex-[2] items-center gap-2">
            <span className="shrink-0 font-mono text-xs tabular-nums text-muted-foreground">
              {formatTime(scrubValue ?? positionMs)}
            </span>
            <Slider
              value={[scrubValue ?? positionMs]}
              onValueChange={handleScrubChange}
              onValueCommit={handleScrubCommit}
              min={0}
              max={Math.max(durationMs, 1)}
              step={100}
              disabled={durationMs <= 0}
              className="w-full"
            />
            <span className="shrink-0 font-mono text-xs tabular-nums text-muted-foreground">
              {formatTime(durationMs)}
            </span>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={handleBack10}
            title="Back 10s"
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={handleTogglePlay}
            title={paused ? "Play" : "Pause"}
          >
            {paused ? <Play className="h-4 w-4" /> : <Pause className="h-4 w-4" />}
          </Button>
          <div className="flex w-28 items-center gap-2">
            <span className="shrink-0 text-xs text-muted-foreground">Guide</span>
            <Slider
              value={[vocalsVolume]}
              onValueChange={handleVolumeChange}
              min={0}
              max={100}
              step={5}
              className="w-full"
            />
          </div>
          <Button variant="ghost" size="icon" onClick={handleStop} title="Stop">
            <Square className="h-4 w-4" />
          </Button>
        </div>

        <KaraokeLyrics
          lines={lyrics}
          positionMs={latest?.song_position_ms ?? null}
        />

        <StatusRow
          score={latest?.score ?? null}
          combo={latest?.combo ?? null}
          stars={latest?.stars ?? null}
        />

        <ResultsScreen
          open={results !== null}
          stars={results?.stars ?? null}
          score={results?.score ?? null}
          bestCombo={results?.bestCombo ?? null}
          songTitle={results?.songTitle}
          notes={results?.notes ?? []}
          onDone={handleStop}
        />
      </div>
    )
  }

  return (
    <div className="flex size-full flex-col">
      <div className="shrink-0 px-6 py-4">
        <h2 className="text-lg font-semibold">Choose a Song</h2>
        <p className="text-sm text-muted-foreground">
          Pick a track to sing along to
        </p>
      </div>

      {loading ? (
        <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
          Loading songs…
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {songs.map((song) => {
              const isPreviewing = preview.previewingId === song.id
              return (
                <button
                  key={song.id}
                  onClick={() => handleSelect(song)}
                  className="group flex flex-col gap-2 rounded-lg border border-border bg-card p-3 text-left transition-colors hover:border-accent-foreground/20 hover:bg-accent"
                >
                  <div className="relative">
                    <img
                      src={`${API_BASE}${song.album_art_url}`}
                      alt={song.title}
                      className="aspect-square w-full rounded object-cover"
                    />
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation()
                        preview.toggle(song)
                      }}
                      aria-label={isPreviewing ? "Stop preview" : "Preview"}
                      className="absolute right-2 top-2 flex size-8 items-center justify-center rounded-full bg-background/80 text-foreground shadow-sm backdrop-blur transition-colors hover:bg-background"
                    >
                      {isPreviewing ? (
                        <Square className="size-4" />
                      ) : (
                        <Play className="size-4" />
                      )}
                    </button>
                  </div>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium leading-tight">
                      {song.title}
                    </p>
                    <div className="flex items-baseline justify-between gap-2 text-xs text-muted-foreground">
                      <p className="truncate">{song.artist}</p>
                      <span className="shrink-0 tabular-nums">
                        {formatTime(song.duration_ms)}
                      </span>
                    </div>
                  </div>
                </button>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
