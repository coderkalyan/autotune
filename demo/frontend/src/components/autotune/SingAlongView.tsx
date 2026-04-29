import { useCallback, useEffect, useState } from "react"
import { Square } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { KaraokeLyrics } from "@/components/autotune/KaraokeLyrics"
import { PulsingBorder } from "@/components/autotune/PulsingBorder"
import { ResultsScreen } from "@/components/autotune/ResultsScreen"
import { StatusRow } from "@/components/autotune/StatusRow"
import { API_BASE } from "@/config"
import type { SongPlayback } from "@/hooks/useSongPlayback"
import type { LyricLine, PitchReading, SongEntry } from "@/types"

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
}

export function SingAlongView({ latest, playback }: Props) {
  const [songs, setSongs] = useState<SongEntry[]>([])
  const [activeSong, setActiveSong] = useState<SongEntry | null>(null)
  const [loading, setLoading] = useState(true)
  const [lyrics, setLyrics] = useState<LyricLine[]>([])
  const [vocalsVolume, setVocalsVolume] = useState(30)
  const [results, setResults] = useState<ResultsSnapshot | null>(null)

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
    const [, lyricsData] = await Promise.all([
      fetch(`${API_BASE}/songs/${song.id}/start`, { method: "POST" }),
      fetch(`${API_BASE}/songs/${song.id}/lyrics`)
        .then((r) => r.json())
        .catch(() => []),
    ])
    setLyrics(lyricsData)
    setActiveSong(song)
    setResults(null)
    playback.setVocalsVolume(vocalsVolume / 100)
    await playback.play(song.id)
  }

  async function handleStop() {
    playback.stop()
    await fetch(`${API_BASE}/songs/stop`, { method: "POST" })
    setActiveSong(null)
    setLyrics([])
    setResults(null)
  }

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
      })
    }
  }, [latest, activeSong, results])

  // Stop audio when this view unmounts (mode switch or back navigation)
  useEffect(() => {
    return () => {
      if (activeSong) {
        playback.stop()
        fetch(`${API_BASE}/songs/stop`, { method: "POST" }).catch(() => {})
      }
    }
  }, [activeSong, playback])

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
            {songs.map((song) => (
              <button
                key={song.id}
                onClick={() => handleSelect(song)}
                className="group flex flex-col gap-2 rounded-lg border border-border bg-card p-3 text-left transition-colors hover:border-accent-foreground/20 hover:bg-accent"
              >
                <img
                  src={`${API_BASE}${song.album_art_url}`}
                  alt={song.title}
                  className="aspect-square w-full rounded object-cover"
                />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium leading-tight">
                    {song.title}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    {song.artist}
                  </p>
                </div>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
