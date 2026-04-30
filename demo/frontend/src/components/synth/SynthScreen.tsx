import { useEffect, useMemo, useRef } from "react"
import { Separator } from "@/components/ui/separator"
import { BackButton } from "@/components/shared/BackButton"
import { SystemStatus } from "@/components/shared/SystemStatus"
import {
  PianoKeyboard,
  buildKeyboardGeometry,
  DEFAULT_MIDI_LOW,
  DEFAULT_MIDI_HIGH,
  type KeyHighlight,
} from "@/components/shared/PianoKeyboard"
import type { AppScreen, PitchReading } from "@/types"

const PIXELS_PER_SECOND = 240
const KEYBOARD_HEIGHT_PX = 180
const HOT_PINK = "#ff2d92"
const PALETTE = [
  "#ff1493",
  "#ff4fbd",
  "#ec4899",
  "#d946ef",
  "#f43f5e",
]

interface RisingNote {
  id: number
  midi: number
  startMs: number
  endMs: number | null
  color: string
}

interface Props {
  onNavigate: (screen: AppScreen) => void
  latest: PitchReading | null
  connected: boolean
  sendMessage: (msg: object) => void
}

export function SynthScreen({ onNavigate, latest, connected, sendMessage }: Props) {
  const geom = useMemo(
    () => buildKeyboardGeometry(DEFAULT_MIDI_LOW, DEFAULT_MIDI_HIGH),
    []
  )
  const { xRangeForMidi } = geom

  const activeNotes = useMemo(
    () => new Set(latest?.midi_notes ?? []),
    [latest?.midi_notes]
  )

  const highlights = useMemo(() => {
    const m = new Map<number, KeyHighlight>()
    activeNotes.forEach((midi) => {
      m.set(midi, { key: HOT_PINK, bloom: PALETTE[midi % PALETTE.length] })
    })
    return m
  }, [activeNotes])

  const panelRef = useRef<HTMLDivElement>(null)
  const idRef = useRef(0)
  const prevActiveRef = useRef<Set<number>>(new Set())
  const risingRef = useRef<RisingNote[]>([])
  const noteElsRef = useRef<Map<number, HTMLDivElement>>(new Map())

  useEffect(() => {
    const now = performance.now()
    const prev = prevActiveRef.current
    activeNotes.forEach((m) => {
      if (!prev.has(m)) {
        risingRef.current.push({
          id: idRef.current++,
          midi: m,
          startMs: now,
          endMs: null,
          color: PALETTE[m % PALETTE.length],
        })
      }
    })
    prev.forEach((m) => {
      if (!activeNotes.has(m)) {
        for (let i = risingRef.current.length - 1; i >= 0; i--) {
          const n = risingRef.current[i]
          if (n.midi === m && n.endMs === null) {
            n.endMs = now
            break
          }
        }
      }
    })
    prevActiveRef.current = new Set(activeNotes)
  }, [activeNotes])

  useEffect(() => {
    let raf = 0
    const S = PIXELS_PER_SECOND / 1000

    const tick = () => {
      const now = performance.now()
      const panel = panelRef.current
      const panelHeight = panel?.clientHeight ?? 0

      const keep: RisingNote[] = []
      for (const n of risingRef.current) {
        const bottom = n.endMs === null ? 0 : (now - n.endMs) * S
        const height = ((n.endMs ?? now) - n.startMs) * S

        if (bottom > panelHeight + 8) {
          const stale = noteElsRef.current.get(n.id)
          if (stale) {
            stale.remove()
            noteElsRef.current.delete(n.id)
          }
          continue
        }

        let el = noteElsRef.current.get(n.id)
        if (!el && panel) {
          el = document.createElement("div")
          el.className = "absolute rounded-md"
          const range = xRangeForMidi(n.midi)
          el.style.left = range.left
          el.style.width = range.width
          el.style.background = `linear-gradient(to top, ${n.color} 0%, ${n.color} 60%, color-mix(in srgb, ${n.color} 40%, white) 100%)`
          el.style.boxShadow = `0 0 18px 2px ${n.color}, 0 0 38px 6px color-mix(in srgb, ${n.color} 55%, transparent), inset 0 0 10px color-mix(in srgb, ${n.color} 30%, white)`
          el.style.opacity = "0.95"
          panel.appendChild(el)
          noteElsRef.current.set(n.id, el)
        }
        if (el) {
          el.style.bottom = `${bottom}px`
          el.style.height = `${Math.max(2, height)}px`
        }
        keep.push(n)
      }
      risingRef.current = keep

      raf = requestAnimationFrame(tick)
    }

    raf = requestAnimationFrame(tick)
    return () => {
      cancelAnimationFrame(raf)
      noteElsRef.current.forEach((el) => el.remove())
      noteElsRef.current.clear()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="flex size-full flex-col">
      <div className="flex shrink-0 items-center px-4 py-2">
        <div className="flex flex-1 justify-start">
          <BackButton onNavigate={onNavigate} />
        </div>
        <h1 className="text-lg font-semibold">Synth</h1>
        <div className="flex flex-1 justify-end">
          <SystemStatus connected={connected} latest={latest} />
        </div>
      </div>

      <Separator />

      <div className="flex min-h-0 flex-1 flex-col bg-gradient-to-b from-background to-muted/20 px-4 pb-6">
        <div className="relative min-h-0 flex-1 px-2">
          <div ref={panelRef} className="relative size-full overflow-hidden" />
        </div>

        <div
          className="relative shrink-0 rounded-2xl bg-neutral-900/60 p-2 shadow-[0_20px_60px_-20px_rgba(0,0,0,0.6)] ring-1 ring-white/5"
          style={{ height: `${KEYBOARD_HEIGHT_PX + 16}px` }}
        >
          <div
            className="pointer-events-none absolute -top-3 inset-x-6 h-3 rounded-full opacity-80 blur-md"
            style={{
              background: `linear-gradient(to right, transparent, ${HOT_PINK}, transparent)`,
            }}
          />
          <div
            className="pointer-events-none absolute inset-x-2 top-2 h-px rounded-full opacity-60"
            style={{
              background:
                "linear-gradient(to right, transparent, rgba(255,255,255,0.45), transparent)",
            }}
          />

          <PianoKeyboard
            highlights={highlights}
            heightPx={KEYBOARD_HEIGHT_PX}
            onPointerDown={(midi) =>
              sendMessage({ type: "midi_note_on", note: midi, velocity: 100 })
            }
            onPointerUp={(midi) => sendMessage({ type: "midi_note_off", note: midi })}
          />
        </div>
      </div>
    </div>
  )
}
