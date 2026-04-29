import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Square } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { PitchGraph } from "@/components/graph/PitchGraph"
import { ScoreDisplay } from "@/components/autotune/ScoreDisplay"
import { ResultsScreen } from "@/components/autotune/ResultsScreen"
import { API_BASE } from "@/config"
import type { LyricLine, NoteCompleted, PitchReading, SongEntry } from "@/types"

const WORD_GLOW_THRESHOLD = 0.6
const WORD_GLOW_DURATION_MS = 500

interface Props {
  readings: PitchReading[]
  latest?: PitchReading | null
}

interface ResultsSnapshot {
  stars: number | null
  score: number | null
  bestCombo: number | null
  songTitle?: string
}

export function SingAlongView({ readings, latest }: Props) {
  const [songs, setSongs] = useState<SongEntry[]>([])
  const [activeSong, setActiveSong] = useState<SongEntry | null>(null)
  const [loading, setLoading] = useState(true)
  const [lyrics, setLyrics] = useState<LyricLine[]>([])
  const [vocalsVolume, setVocalsVolume] = useState(30)
  const [results, setResults] = useState<ResultsSnapshot | null>(null)

  // Word-glow latch: most recent successful note's lyric + expiry timestamp.
  const [glowWord, setGlowWord] = useState<{ lyric: string; until: number } | null>(null)
  const lastNoteRef = useRef<NoteCompleted | null>(null)

  const handleVolumeChange = useCallback((value: number[]) => {
    const v = value[0]
    setVocalsVolume(v)
    fetch(`${API_BASE}/songs/vocals_volume?volume=${v / 100}`, { method: "POST" }).catch(() => {})
  }, [])

  useEffect(() => {
    fetch(`${API_BASE}/songs`)
      .then((r) => r.json())
      .then((data) => setSongs(data))
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [])

  async function handleSelect(song: SongEntry) {
    const [, lyricsData] = await Promise.all([
      fetch(`${API_BASE}/songs/${song.id}/play`, { method: "POST" }),
      fetch(`${API_BASE}/songs/${song.id}/lyrics`).then((r) => r.json()).catch(() => []),
    ])
    setLyrics(lyricsData)
    setActiveSong(song)
    setResults(null)
    lastNoteRef.current = null
    setGlowWord(null)
  }

  async function handleStop() {
    await fetch(`${API_BASE}/songs/stop`, { method: "POST" })
    setActiveSong(null)
    setLyrics([])
    setResults(null)
  }

  // Watch for song completion and snapshot results so we can keep the dialog
  // open after the backend tears down the scoring session.
  useEffect(() => {
    if (!latest || !activeSong) return
    if (latest.song_complete && results === null) {
      setResults({
        stars: latest.stars ?? 0,
        score: latest.score ?? 0,
        bestCombo: latest.best_combo ?? 0,
        songTitle: activeSong.title,
      })
    }
  }, [latest, activeSong, results])

  // Word glow: when a new note_completed arrives with a passing score, latch
  // its lyric for a short window so the karaoke text can pulse it.
  useEffect(() => {
    const note = latest?.note_completed
    if (!note) return
    if (note === lastNoteRef.current) return
    lastNoteRef.current = note
    if (note.score >= WORD_GLOW_THRESHOLD && note.lyric) {
      setGlowWord({
        lyric: note.lyric,
        until: (typeof performance !== "undefined" ? performance.now() : Date.now()) + WORD_GLOW_DURATION_MS,
      })
    }
  }, [latest])

  // Stop audio when this view unmounts (mode switch or back navigation)
  useEffect(() => {
    return () => {
      if (activeSong) {
        fetch(`${API_BASE}/songs/stop`, { method: "POST" }).catch(() => {})
      }
    }
  }, [activeSong])

  // Stop audio when the browser tab is closed or refreshed
  useEffect(() => {
    if (!activeSong) return
    const handleUnload = () => navigator.sendBeacon(`${API_BASE}/songs/stop`)
    const handleVisibility = () => { if (document.visibilityState === "hidden") handleUnload() }
    window.addEventListener("pagehide", handleUnload)
    document.addEventListener("visibilitychange", handleVisibility)
    return () => {
      window.removeEventListener("pagehide", handleUnload)
      document.removeEventListener("visibilitychange", handleVisibility)
    }
  }, [activeSong])

  if (activeSong) {
    return (
      <div className="flex size-full flex-col">
        {/* Now-playing strip */}
        <div className="flex shrink-0 items-center gap-3 border-b border-border px-4 py-2">
          <img
            src={`${API_BASE}${activeSong.album_art_url}`}
            alt={activeSong.title}
            className="h-10 w-10 rounded object-cover"
          />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold leading-tight">{activeSong.title}</p>
            <p className="truncate text-xs text-muted-foreground">{activeSong.artist}</p>
          </div>
          <div className="flex items-center gap-2 w-28">
            <span className="text-xs text-muted-foreground shrink-0">Guide</span>
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

        {/* Score + combo strip */}
        <ScoreDisplay
          score={latest?.score ?? null}
          combo={latest?.combo ?? null}
          bestCombo={latest?.best_combo ?? null}
        />

        {/* Lyrics */}
        {lyrics.length > 0 && (
          <KaraokeDisplay
            lyrics={lyrics}
            positionMs={latest?.song_position_ms ?? null}
            glowWord={glowWord}
          />
        )}

        {/* Pitch graph */}
        <div className="min-h-0 flex-1 p-4">
          <PitchGraph readings={readings} showTarget={true} />
        </div>

        <ResultsScreen
          open={results !== null}
          stars={results?.stars ?? null}
          score={results?.score ?? null}
          bestCombo={results?.bestCombo ?? null}
          songTitle={results?.songTitle}
          onDone={handleStop}
        />
      </div>
    )
  }

  return (
    <div className="flex size-full flex-col">
      <div className="shrink-0 px-6 py-4">
        <h2 className="text-lg font-semibold">Choose a Song</h2>
        <p className="text-sm text-muted-foreground">Pick a track to sing along to</p>
      </div>

      {loading ? (
        <div className="flex flex-1 items-center justify-center text-muted-foreground text-sm">
          Loading songs…
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {songs.map((song) => (
              <button
                key={song.id}
                onClick={() => handleSelect(song)}
                className="group flex flex-col gap-2 rounded-lg border border-border bg-card p-3 text-left transition-colors hover:bg-accent hover:border-accent-foreground/20"
              >
                <img
                  src={`${API_BASE}${song.album_art_url}`}
                  alt={song.title}
                  className="aspect-square w-full rounded object-cover"
                />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium leading-tight">{song.title}</p>
                  <p className="truncate text-xs text-muted-foreground">{song.artist}</p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------

interface KaraokeProps {
  lyrics: LyricLine[]
  positionMs: number | null
  glowWord: { lyric: string; until: number } | null
}

function KaraokeDisplay({ lyrics, positionMs, glowWord }: KaraokeProps) {
  const pos = positionMs ?? 0

  // Find current line index
  const lineIdx = useMemo(() => {
    let idx = -1
    for (let i = 0; i < lyrics.length; i++) {
      if (lyrics[i].timestamp_ms <= pos) idx = i
      else break
    }
    return idx
  }, [lyrics, pos])

  const line = lineIdx >= 0 ? lyrics[lineIdx] : null

  // Re-render on a short interval so the glow class clears when its window expires.
  const [, setTick] = useState(0)
  useEffect(() => {
    if (!glowWord) return
    const remaining = glowWord.until - (typeof performance !== "undefined" ? performance.now() : Date.now())
    if (remaining <= 0) return
    const t = setTimeout(() => setTick((n) => n + 1), Math.max(40, remaining + 16))
    return () => clearTimeout(t)
  }, [glowWord])

  const now = typeof performance !== "undefined" ? performance.now() : Date.now()
  const glowActive = glowWord && glowWord.until > now ? glowWord.lyric : null

  return (
    <div className="shrink-0 flex items-center justify-center min-h-16 px-6 py-2">
      {line && (
        line.words ? (
          <p className="text-2xl font-semibold text-center tracking-wide leading-snug">
            {line.words.map((w, i) => {
              const nextWord = line.words![i + 1]
              const wordEnd = w.end_ms ?? (nextWord?.timestamp_ms ?? (line.timestamp_ms + 5000))
              const active = pos >= w.timestamp_ms && pos < wordEnd
              const past = pos >= wordEnd
              const glow = glowActive !== null && glowActive === w.text && past
              return (
                <span
                  key={i}
                  className={
                    (glow
                      ? "text-primary drop-shadow-[0_0_6px_var(--primary)] "
                      : "") +
                    (active
                      ? "text-primary transition-colors duration-75"
                      : past
                      ? "text-muted-foreground transition-colors duration-150"
                      : "text-foreground/40 transition-colors duration-150")
                  }
                >
                  {w.text}{" "}
                </span>
              )
            })}
          </p>
        ) : (
          <p key={line.timestamp_ms} className="text-2xl font-semibold text-center tracking-wide animate-in fade-in duration-300">
            {line.text}
          </p>
        )
      )}
    </div>
  )
}
