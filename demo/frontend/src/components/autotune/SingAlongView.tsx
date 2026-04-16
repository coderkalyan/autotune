import { useEffect, useState } from "react"
import { Square } from "lucide-react"
import { Button } from "@/components/ui/button"
import { PitchGraph } from "@/components/graph/PitchGraph"
import { API_BASE } from "@/config"
import type { PitchReading, SongEntry } from "@/types"

interface Props {
  readings: PitchReading[]
  latest?: PitchReading | null
}

export function SingAlongView({ readings }: Props) {
  const [songs, setSongs] = useState<SongEntry[]>([])
  const [activeSong, setActiveSong] = useState<SongEntry | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch(`${API_BASE}/songs`)
      .then((r) => r.json())
      .then((data) => setSongs(data))
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [])

  async function handleSelect(song: SongEntry) {
    await fetch(`${API_BASE}/songs/${song.id}/play`, { method: "POST" })
    setActiveSong(song)
  }

  async function handleStop() {
    await fetch(`${API_BASE}/songs/stop`, { method: "POST" })
    setActiveSong(null)
  }

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
          <Button variant="ghost" size="icon" onClick={handleStop} title="Stop">
            <Square className="h-4 w-4" />
          </Button>
        </div>

        {/* Pitch graph */}
        <div className="min-h-0 flex-1 p-4">
          <PitchGraph readings={readings} showTarget={true} />
        </div>
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
