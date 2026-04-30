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

  // Harmony-mode telemetry (mirrors demo/backend/uart_parser.py)
  melody_midi?: number | null            // MIDI note feeding harmony_gen
  held_midi?: number | null              // priority-encoder MIDI of held keys
  any_note_pressed?: boolean | null
  harm1_midi?: number | null             // first harmony voice MIDI
  harm2_midi?: number | null             // second harmony voice MIDI
  harm_tonic?: number | null             // 0=C..11=B
  harm_mode?: number | null              // 0=major, 1=minor
  harm_key_name?: string | null          // e.g. "A minor"
  chord_state?: number | null            // Markov state 1..7
  in_scale?: boolean | null
  melody_note_name?: string | null       // e.g. "A4"
  harm1_note_name?: string | null
  harm2_note_name?: string | null

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

  // Grading window (driven by song meta.json grade_start_ms / grade_end_ms).
  // Outside the window scoring is paused, vocals get boosted, and the UI shows
  // a "Get Ready" / "Nice work" banner instead of grading state.
  grade_start_ms?: number | null
  grade_end_ms?: number | null
  grade_complete?: boolean | null   // true once position passes grade_end_ms
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
  key?: string | null
}

export type AutotuneSubMode = "free" | "sing-along"

export type AppScreen =
  | { screen: "splash" }
  | { screen: "autotune"; subMode: AutotuneSubMode; selectedSong: SongEntry | null }
  | { screen: "vocoder" }
  | { screen: "synth" }
  | { screen: "harmony" }
