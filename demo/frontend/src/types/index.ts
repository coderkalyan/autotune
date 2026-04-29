export type UARTMode = 0 | 1 | 2 | 3 // MUTE | PASSTHROUGH | AUTOTUNE | VOCODE

export interface PitchReading {
  detected_hz: number | null
  corrected_hz: number | null
  detected_held: number | null  // last known good value when VAD is inactive
  corrected_held: number | null
  target_hz: number | null
  lyric?: string | null
  song_position_ms?: number | null
  timestamp_ms: number
  mode: UARTMode | null
  vad_active: boolean | null
  vad_voiced: boolean | null
  dac_full: boolean | null
  adc_empty: boolean | null
  config_done: boolean | null
  config_err: boolean | null
  vocode_bands: number[] | null  // 32 Q11.16 values converted to float

  // Karaoke scoring (sing-along mode)
  detected_hit?: number | null
  detected_near?: number | null
  detected_miss?: number | null
  target_hz_display?: number | null
  score?: number | null            // 0..1
  combo?: number | null
  best_combo?: number | null
  note_completed?: NoteCompleted | null
  stars?: number | null            // 0..5; final once song_complete=true
  song_complete?: boolean | null
}

export interface NoteCompleted {
  lyric: string
  pitch_hz: number
  score: number
}

export interface LyricWord {
  timestamp_ms: number
  end_ms: number | null
  text: string
}

export interface LyricLine {
  timestamp_ms: number
  text: string
  words?: LyricWord[]
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
