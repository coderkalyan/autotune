const NOTE_NAMES = [
  "C",
  "C#",
  "D",
  "D#",
  "E",
  "F",
  "F#",
  "G",
  "G#",
  "A",
  "A#",
  "B",
] as const

export interface NoteInfo {
  name: string
  cents: number
}

export function hzToNote(hz: number): NoteInfo {
  const midiFloat = 12 * Math.log2(hz / 440) + 69
  const midi = Math.round(midiFloat)
  const cents = (midiFloat - midi) * 100
  const pitchClass = ((midi % 12) + 12) % 12
  const octave = Math.floor(midi / 12) - 1
  return { name: `${NOTE_NAMES[pitchClass]}${octave}`, cents }
}

export interface FormatOptions {
  showCents?: boolean
}

export function formatNote(
  hz: number | null | undefined,
  opts: FormatOptions = {},
): string {
  if (hz == null || !Number.isFinite(hz) || hz <= 0) return "—"
  const { name, cents } = hzToNote(hz)
  if (!opts.showCents) return name
  const rounded = Math.round(cents)
  const sign = rounded >= 0 ? "+" : "−"
  return `${name} ${sign}${Math.abs(rounded)}¢`
}

export function formatCents(cents: number | null | undefined): string {
  if (cents == null || !Number.isFinite(cents)) return "—"
  const rounded = Math.round(cents)
  const sign = rounded >= 0 ? "+" : "−"
  return `${sign}${Math.abs(rounded)}¢`
}
