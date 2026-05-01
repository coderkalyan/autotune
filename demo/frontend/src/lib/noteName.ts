const NOTE_NAMES_SHARP = [
  "C",
  "C♯",
  "D",
  "D♯",
  "E",
  "F",
  "F♯",
  "G",
  "G♯",
  "A",
  "A♯",
  "B",
] as const

const NOTE_NAMES_FLAT = [
  "C",
  "D♭",
  "D",
  "E♭",
  "E",
  "F",
  "G♭",
  "G",
  "A♭",
  "A",
  "B♭",
  "B",
] as const

const FLAT_CAMELOT_CODES = new Set([
  "2A",
  "3A",
  "3B",
  "4A",
  "4B",
  "5A",
  "5B",
  "6A",
  "6B",
  "7B",
])

export function keyUsesFlats(key: string | null | undefined): boolean {
  if (!key) return false
  return FLAT_CAMELOT_CODES.has(key.trim().toUpperCase())
}

export interface NoteInfo {
  name: string
  cents: number
}

export function hzToNote(hz: number, useFlats = false): NoteInfo {
  const midiFloat = 12 * Math.log2(hz / 440) + 69
  const midi = Math.round(midiFloat)
  const cents = (midiFloat - midi) * 100
  const pitchClass = ((midi % 12) + 12) % 12
  const octave = Math.floor(midi / 12) - 1
  const table = useFlats ? NOTE_NAMES_FLAT : NOTE_NAMES_SHARP
  return { name: `${table[pitchClass]}${octave}`, cents }
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

export function formatNoteInKey(
  hz: number | null | undefined,
  key: string | null | undefined,
  opts: FormatOptions = {},
): string {
  if (hz == null || !Number.isFinite(hz) || hz <= 0) return "—"
  const { name, cents } = hzToNote(hz, keyUsesFlats(key))
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
