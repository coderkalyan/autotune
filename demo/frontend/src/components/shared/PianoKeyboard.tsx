import { useMemo, type PointerEvent } from "react"

export const DEFAULT_MIDI_LOW = 36 // C2
export const DEFAULT_MIDI_HIGH = 96 // C7
const BLACK_WIDTH_RATIO = 0.6
const BLACK_HEIGHT_RATIO = 0.62
const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const WHITE_SEMI = new Set([0, 2, 4, 5, 7, 9, 11])

export interface KeyMeta {
  midi: number
  isWhite: boolean
  whiteIndex: number
}

export interface KeyboardGeometry {
  keys: KeyMeta[]
  whiteCount: number
  whiteWidthPct: number
  blackWidthPct: number
  metaByMidi: Map<number, KeyMeta>
  xRangeForMidi: (midi: number) => { left: string; width: string }
  xCenterPctForMidi: (midi: number) => number
}

export function buildKeyboardGeometry(low: number, high: number): KeyboardGeometry {
  const keys: KeyMeta[] = []
  const metaByMidi = new Map<number, KeyMeta>()
  let whiteCount = 0
  for (let m = low; m <= high; m++) {
    const isWhite = WHITE_SEMI.has(m % 12)
    const meta: KeyMeta = isWhite
      ? { midi: m, isWhite: true, whiteIndex: whiteCount }
      : { midi: m, isWhite: false, whiteIndex: whiteCount - 1 }
    keys.push(meta)
    metaByMidi.set(m, meta)
    if (isWhite) whiteCount++
  }
  const whiteWidthPct = 100 / whiteCount
  const blackWidthPct = whiteWidthPct * BLACK_WIDTH_RATIO

  const xRangeForMidi = (midi: number): { left: string; width: string } => {
    const meta = metaByMidi.get(midi)
    if (!meta) return { left: "0%", width: "0%" }
    if (meta.isWhite) {
      return { left: `${meta.whiteIndex * whiteWidthPct}%`, width: `${whiteWidthPct}%` }
    }
    const center = (meta.whiteIndex + 1) * whiteWidthPct
    return { left: `${center - blackWidthPct / 2}%`, width: `${blackWidthPct}%` }
  }

  const xCenterPctForMidi = (midi: number): number => {
    const meta = metaByMidi.get(midi)
    if (!meta) return 0
    if (meta.isWhite) return (meta.whiteIndex + 0.5) * whiteWidthPct
    return (meta.whiteIndex + 1) * whiteWidthPct
  }

  return { keys, whiteCount, whiteWidthPct, blackWidthPct, metaByMidi, xRangeForMidi, xCenterPctForMidi }
}

export function midiToNoteName(m: number): string {
  return NOTE_NAMES[m % 12] + (Math.floor(m / 12) - 1)
}

export interface KeyHighlight {
  /** Color used for the pressed-key gradient. */
  key: string
  /** Optional separate color for the radial light bleed. Defaults to `key`. */
  bloom?: string
}

interface Props {
  highlights: Map<number, KeyHighlight>
  lowMidi?: number
  highMidi?: number
  heightPx?: number
  onPointerDown?: (midi: number, e: PointerEvent<HTMLDivElement>) => void
  onPointerUp?: (midi: number, e: PointerEvent<HTMLDivElement>) => void
}

export function PianoKeyboard({
  highlights,
  lowMidi = DEFAULT_MIDI_LOW,
  highMidi = DEFAULT_MIDI_HIGH,
  heightPx = 180,
  onPointerDown,
  onPointerUp,
}: Props) {
  const geom = useMemo(() => buildKeyboardGeometry(lowMidi, highMidi), [lowMidi, highMidi])
  const { keys, whiteWidthPct, xRangeForMidi, xCenterPctForMidi } = geom
  const blackKeys = keys.filter((k) => !k.isWhite)
  const whiteKeys = keys.filter((k) => k.isWhite)
  const showLabel = (midi: number) => midi % 12 === 0

  const interactive = !!onPointerDown
  const cursorClass = interactive ? "cursor-pointer" : ""

  // Pointer-capture: track per-pointerId midi so up/cancel sends the right note off
  const pointerNoteRef = useMemo(() => new Map<number, number>(), [])
  const handleDown = (midi: number) => (e: PointerEvent<HTMLDivElement>) => {
    if (!onPointerDown) return
    e.preventDefault()
    e.currentTarget.setPointerCapture(e.pointerId)
    pointerNoteRef.set(e.pointerId, midi)
    onPointerDown(midi, e)
  }
  const handleUp = (e: PointerEvent<HTMLDivElement>) => {
    const midi = pointerNoteRef.get(e.pointerId)
    if (midi === undefined || !onPointerUp) return
    pointerNoteRef.delete(e.pointerId)
    onPointerUp(midi, e)
  }

  const whiteGradient = (h: KeyHighlight | undefined) =>
    h
      ? `linear-gradient(to bottom, color-mix(in srgb, ${h.key} 55%, white) 0%, ${h.key} 100%)`
      : "linear-gradient(to bottom, #fafafa 0%, #ececec 60%, #d4d4d4 100%)"
  const blackGradient = (h: KeyHighlight | undefined) =>
    h
      ? `linear-gradient(to bottom, color-mix(in srgb, ${h.key} 70%, white) 0%, color-mix(in srgb, ${h.key} 80%, black) 100%)`
      : "linear-gradient(to bottom, #2a2a2a 0%, #0a0a0a 70%, #1a1a1a 100%)"

  return (
    <div
      className="relative overflow-hidden rounded-xl ring-1 ring-black/40"
      style={{ height: `${heightPx}px` }}
    >
      <div className="absolute inset-0 flex">
        {whiteKeys.map((k, i) => {
          const hl = highlights.get(k.midi)
          return (
            <div
              key={k.midi}
              onPointerDown={handleDown(k.midi)}
              onPointerUp={handleUp}
              onPointerCancel={handleUp}
              className={`group relative flex-1 ${cursorClass} touch-none select-none overflow-hidden border-r border-black/30 last:border-r-0 ${
                i === 0 ? "rounded-bl-lg" : ""
              } ${i === whiteKeys.length - 1 ? "rounded-br-lg" : ""} transition-[background] duration-75`}
              style={{ background: whiteGradient(hl) }}
            >
              <div
                className="pointer-events-none absolute inset-0 opacity-[0.07] mix-blend-multiply"
                style={{
                  backgroundImage:
                    "repeating-linear-gradient(90deg, rgba(0,0,0,0.6) 0px, rgba(0,0,0,0.6) 1px, transparent 1px, transparent 6px)",
                }}
              />
              <div className="pointer-events-none absolute inset-x-0 top-0 h-2 bg-gradient-to-b from-white/80 to-transparent" />
              <div className="pointer-events-none absolute inset-x-0 bottom-0 h-3 bg-gradient-to-t from-black/25 to-transparent" />
              {showLabel(k.midi) && (
                <span className="pointer-events-none absolute inset-x-0 bottom-2 text-center text-[10px] font-semibold text-neutral-700">
                  {midiToNoteName(k.midi)}
                </span>
              )}
            </div>
          )
        })}
      </div>

      {blackKeys.map((k) => {
        const range = xRangeForMidi(k.midi)
        const hl = highlights.get(k.midi)
        return (
          <div
            key={k.midi}
            onPointerDown={handleDown(k.midi)}
            onPointerUp={handleUp}
            onPointerCancel={handleUp}
            className={`absolute top-0 ${cursorClass} touch-none select-none overflow-hidden rounded-b-lg shadow-[0_4px_8px_rgba(0,0,0,0.5)] transition-[background] duration-75`}
            style={{
              left: range.left,
              width: range.width,
              height: `${heightPx * BLACK_HEIGHT_RATIO}px`,
              background: blackGradient(hl),
            }}
          >
            <div className="pointer-events-none absolute inset-x-1 top-0.5 h-px rounded-full bg-white/30" />
            <div className="pointer-events-none absolute inset-y-0 left-0 w-px bg-white/10" />
            <div className="pointer-events-none absolute inset-y-0 right-0 w-px bg-black/60" />
            <div className="pointer-events-none absolute inset-x-0 bottom-0 h-2 bg-gradient-to-t from-white/15 to-transparent" />
          </div>
        )
      })}

      {/* Per-key radial light bleed. */}
      <div className="pointer-events-none absolute inset-0" style={{ mixBlendMode: "screen" }}>
        {Array.from(highlights.entries()).map(([m, h]) => {
          const cx = xCenterPctForMidi(m)
          const color = h.bloom ?? h.key
          const spread = whiteWidthPct * 5
          return (
            <div
              key={m}
              className="absolute top-0 -translate-x-1/2"
              style={{
                left: `${cx}%`,
                width: `${spread}%`,
                height: "100%",
                background: `radial-gradient(ellipse 50% 70% at center 25%, ${color} 0%, color-mix(in srgb, ${color} 60%, transparent) 25%, transparent 65%)`,
                filter: "blur(2px)",
              }}
            />
          )
        })}
      </div>
    </div>
  )
}
