export type UARTMode = 0 | 1 | 2 | 3 | 4 | 5 // MUTE | PASSTHROUGH | AUTOTUNE | VOCODE | SYNTH | HARMONY

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
  midi_notes?: number[] | null   // currently held MIDI notes (Synth mode visualization)

  // Karaoke scoring (sing-along mode)
  detected_hit?: number | null
  detected_near?: number | null
  detected_miss?: number | null
  target_hz_display?: number | null
  score?: number | null            // 0..1
  combo?: number | null
  best_combo?: number | null
  note_completed?: NoteCompleted | null
  stars?: number | null            // 0..5; updates live, final at song_complete
  song_complete?: boolean | null
  frame_quality?: number | null    // 0..1 EMA of per-frame pitch quality; null = silence
}

export interface NoteCompleted {
  lyric: string
  pitch_hz: number
  score: number
  detected_pitch_hz?: number | null
  cents_off?: number | null
  pitch_score?: number
  timing_score?: number
  duration_ms?: number
  onset_offset_ms?: number | null
  weight?: number
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
  grade_start_ms: number
  grade_end_ms: number
}

export type AutotuneSubMode = "free" | "sing-along"

export type AppScreen =
  | { screen: "splash" }
  | { screen: "autotune"; subMode: AutotuneSubMode; selectedSong: SongEntry | null }
  | { screen: "vocoder" }
  | { screen: "synth" }
