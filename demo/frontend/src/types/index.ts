export interface PitchReading {
  detected_hz: number | null
  corrected_hz: number | null
  target_hz: number | null
  timestamp_ms: number
}

export interface SongEntry {
  id: string
  title: string
  artist: string
  album: string
  duration_ms: number
  album_art_url: string
  bpm: number | null
}

export type AutotuneSubMode = "free" | "sing-along"

export type AppScreen =
  | { screen: "splash" }
  | { screen: "autotune"; subMode: AutotuneSubMode; selectedSong: SongEntry | null }
  | { screen: "vocoder" }
