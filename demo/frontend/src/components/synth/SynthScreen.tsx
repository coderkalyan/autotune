import { useEffect, useMemo, useRef, type PointerEvent } from "react"
import { Separator } from "@/components/ui/separator"
import { BackButton } from "@/components/shared/BackButton"
import { SystemStatus } from "@/components/shared/SystemStatus"
import type { AppScreen, PitchReading } from "@/types"

const MIDI_LOW = 36 // C2
const MIDI_HIGH = 96 // C7
const PIXELS_PER_SECOND = 240
const KEYBOARD_HEIGHT_PX = 180
const BLACK_WIDTH_RATIO = 0.6
const BLACK_HEIGHT_RATIO = 0.62
const HOT_PINK = "#ff2d92"
const PALETTE = [
  "#ff1493", // deep hot pink
  "#ff4fbd", // bright magenta-pink
  "#ec4899", // pink-500
  "#d946ef", // fuchsia-500
  "#f43f5e", // rose-500
]
const PARTICLE_COUNT = 14
const PARTICLE_GRAVITY = 1100 // px/s² downward
const PARTICLE_LIFE_MS = 900
const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const WHITE_SEMI = new Set([0, 2, 4, 5, 7, 9, 11])

interface KeyMeta {
  midi: number
  isWhite: boolean
  whiteIndex: number // For whites: own index. For blacks: index of left-adjacent white.
}

function buildKeys(): { keys: KeyMeta[]; whiteCount: number; metaByMidi: Map<number, KeyMeta> } {
  const keys: KeyMeta[] = []
  const metaByMidi = new Map<number, KeyMeta>()
  let whiteCount = 0
  for (let m = MIDI_LOW; m <= MIDI_HIGH; m++) {
    const isWhite = WHITE_SEMI.has(m % 12)
    const meta: KeyMeta = isWhite
      ? { midi: m, isWhite: true, whiteIndex: whiteCount }
      : { midi: m, isWhite: false, whiteIndex: whiteCount - 1 }
    keys.push(meta)
    metaByMidi.set(m, meta)
    if (isWhite) whiteCount++
  }
  return { keys, whiteCount, metaByMidi }
}

function midiToNoteName(m: number): string {
  return NOTE_NAMES[m % 12] + (Math.floor(m / 12) - 1)
}

interface RisingNote {
  id: number
  midi: number
  startMs: number
  endMs: number | null
  color: string
}

interface Particle {
  id: number
  x: number          // px from panel left
  y: number          // px from panel bottom (positive = up)
  vx: number         // px/s
  vy: number         // px/s (positive = up)
  bornMs: number
  life: number       // ms
  color: string
  size: number
}

interface Props {
  onNavigate: (screen: AppScreen) => void
  latest: PitchReading | null
  connected: boolean
  sendMessage: (msg: object) => void
}

export function SynthScreen({ onNavigate, latest, connected, sendMessage }: Props) {
  const { keys, whiteCount, metaByMidi } = useMemo(buildKeys, [])
  const whiteWidthPct = 100 / whiteCount
  const blackWidthPct = whiteWidthPct * BLACK_WIDTH_RATIO

  const xRangeForMidi = (midi: number): { left: string; width: string } => {
    const meta = metaByMidi.get(midi)!
    if (meta.isWhite) {
      return { left: `${meta.whiteIndex * whiteWidthPct}%`, width: `${whiteWidthPct}%` }
    }
    const center = (meta.whiteIndex + 1) * whiteWidthPct
    return { left: `${center - blackWidthPct / 2}%`, width: `${blackWidthPct}%` }
  }

  const xCenterPctForMidi = (midi: number): number => {
    const meta = metaByMidi.get(midi)!
    if (meta.isWhite) return (meta.whiteIndex + 0.5) * whiteWidthPct
    return (meta.whiteIndex + 1) * whiteWidthPct
  }

  const activeNotes = useMemo(() => new Set(latest?.midi_notes ?? []), [latest?.midi_notes])

  const panelRef = useRef<HTMLDivElement>(null)
  const particleLayerRef = useRef<HTMLDivElement>(null)
  const idRef = useRef(0)
  const prevActiveRef = useRef<Set<number>>(new Set())
  const risingRef = useRef<RisingNote[]>([])
  const noteElsRef = useRef<Map<number, HTMLDivElement>>(new Map())
  const particlesRef = useRef<Particle[]>([])
  const particleElsRef = useRef<Map<number, HTMLDivElement>>(new Map())
  const pointerNoteRef = useRef<Map<number, number>>(new Map())

  const handlePointerDown = (midi: number) => (e: PointerEvent<HTMLDivElement>) => {
    e.preventDefault()
    e.currentTarget.setPointerCapture(e.pointerId)
    pointerNoteRef.current.set(e.pointerId, midi)
    sendMessage({ type: "midi_note_on", note: midi, velocity: 100 })
  }
  const handlePointerUp = (e: PointerEvent<HTMLDivElement>) => {
    const midi = pointerNoteRef.current.get(e.pointerId)
    if (midi === undefined) return
    pointerNoteRef.current.delete(e.pointerId)
    sendMessage({ type: "midi_note_off", note: midi })
  }

  useEffect(() => {
    const now = performance.now()
    const prev = prevActiveRef.current
    const panel = panelRef.current
    activeNotes.forEach((m) => {
      if (!prev.has(m)) {
        risingRef.current.push({
          id: idRef.current++,
          midi: m,
          startMs: now,
          endMs: null,
          color: PALETTE[m % PALETTE.length],
        })

        // Particle burst at the impact point (key x, panel bottom).
        if (panel) {
          const w = panel.clientWidth
          const xPct = xCenterPctForMidi(m)
          const x0 = (xPct / 100) * w
          const color = PALETTE[m % PALETTE.length]
          for (let i = 0; i < PARTICLE_COUNT; i++) {
            const angle = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 0.9
            const speed = 220 + Math.random() * 520
            particlesRef.current.push({
              id: idRef.current++,
              x: x0 + (Math.random() - 0.5) * 6,
              y: 0,
              vx: Math.cos(angle) * speed,
              vy: -Math.sin(angle) * speed, // angle ≈ -π/2 ⇒ vy positive (up)
              bornMs: now,
              life: PARTICLE_LIFE_MS * (0.6 + Math.random() * 0.7),
              color,
              size: 3 + Math.random() * 4,
            })
          }
        }
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

  // Imperative DOM sync: spawn/remove note elements, then animate via RAF.
  useEffect(() => {
    let raf = 0
    let lastNow = performance.now()
    const S = PIXELS_PER_SECOND / 1000

    const tick = () => {
      const now = performance.now()
      const dt = Math.min(0.05, (now - lastNow) / 1000) // clamp big gaps after tab idle
      lastNow = now
      const panel = panelRef.current
      const particleLayer = particleLayerRef.current
      const panelHeight = panel?.clientHeight ?? 0
      const panelWidth = panel?.clientWidth ?? 0

      // --- rising bars ---
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

      // --- particles ---
      const keepP: Particle[] = []
      for (const p of particlesRef.current) {
        const age = now - p.bornMs
        if (age >= p.life || p.x < -20 || p.x > panelWidth + 20 || p.y < -20) {
          const stale = particleElsRef.current.get(p.id)
          if (stale) {
            stale.remove()
            particleElsRef.current.delete(p.id)
          }
          continue
        }
        // Integrate physics.
        p.vy -= PARTICLE_GRAVITY * dt
        p.x += p.vx * dt
        p.y += p.vy * dt

        let el = particleElsRef.current.get(p.id)
        if (!el && particleLayer) {
          el = document.createElement("div")
          el.className = "absolute rounded-full"
          el.style.width = `${p.size}px`
          el.style.height = `${p.size}px`
          el.style.background = p.color
          el.style.boxShadow = `0 0 ${p.size * 3}px ${p.size * 0.6}px ${p.color}, 0 0 ${p.size * 7}px ${p.size}px color-mix(in srgb, ${p.color} 50%, transparent)`
          el.style.willChange = "transform, opacity"
          particleLayer.appendChild(el)
          particleElsRef.current.set(p.id, el)
        }
        if (el) {
          // Use translate3d for GPU compositing; bottom/left as base.
          el.style.left = `${p.x - p.size / 2}px`
          el.style.bottom = `${p.y - p.size / 2}px`
          const t = age / p.life
          el.style.opacity = `${(1 - t) * (1 - t)}` // ease-out fade
        }
        keepP.push(p)
      }
      particlesRef.current = keepP

      raf = requestAnimationFrame(tick)
    }

    raf = requestAnimationFrame(tick)
    return () => {
      cancelAnimationFrame(raf)
      noteElsRef.current.forEach((el) => el.remove())
      noteElsRef.current.clear()
      particleElsRef.current.forEach((el) => el.remove())
      particleElsRef.current.clear()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const blackKeys = keys.filter((k) => !k.isWhite)
  const whiteKeys = keys.filter((k) => k.isWhite)
  const showLabel = (midi: number) => midi % 12 === 0 // C of each octave

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
        {/* Bars + particles inset matches the keyboard inner width (mx-4 outer + p-2 inner ring). */}
        <div className="relative min-h-0 flex-1 px-2">
          <div ref={panelRef} className="relative size-full overflow-hidden">
            {/* Particle layer — sits above bars, additive blend for bloom. */}
            <div
              ref={particleLayerRef}
              className="pointer-events-none absolute inset-0"
              style={{ mixBlendMode: "screen" }}
            />
          </div>
        </div>

        <div
          className="relative shrink-0 rounded-2xl bg-neutral-900/60 p-2 shadow-[0_20px_60px_-20px_rgba(0,0,0,0.6)] ring-1 ring-white/5"
          style={{ height: `${KEYBOARD_HEIGHT_PX + 16}px` }}
        >
          {/* Top-edge glow */}
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

          <div
            className="relative overflow-hidden rounded-xl ring-1 ring-black/40"
            style={{ height: `${KEYBOARD_HEIGHT_PX}px` }}
          >
            <div className="absolute inset-0 flex">
              {whiteKeys.map((k, i) => (
                <div
                  key={k.midi}
                  onPointerDown={handlePointerDown(k.midi)}
                  onPointerUp={handlePointerUp}
                  onPointerCancel={handlePointerUp}
                  className={`group relative flex-1 cursor-pointer touch-none select-none overflow-hidden border-r border-black/30 last:border-r-0 ${
                    i === 0 ? "rounded-bl-lg" : ""
                  } ${i === whiteKeys.length - 1 ? "rounded-br-lg" : ""} transition-[background] duration-75`}
                  style={{
                    background: activeNotes.has(k.midi)
                      ? "linear-gradient(to bottom, #ff8fcf 0%, #ff1493 100%)"
                      : "linear-gradient(to bottom, #fafafa 0%, #ececec 60%, #d4d4d4 100%)",
                  }}
                >
                  {/* Subtle vertical wood-grain stripes for texture */}
                  <div
                    className="pointer-events-none absolute inset-0 opacity-[0.07] mix-blend-multiply"
                    style={{
                      backgroundImage:
                        "repeating-linear-gradient(90deg, rgba(0,0,0,0.6) 0px, rgba(0,0,0,0.6) 1px, transparent 1px, transparent 6px)",
                    }}
                  />
                  {/* Inner top sheen */}
                  <div className="pointer-events-none absolute inset-x-0 top-0 h-2 bg-gradient-to-b from-white/80 to-transparent" />
                  {/* Bottom shadow */}
                  <div className="pointer-events-none absolute inset-x-0 bottom-0 h-3 bg-gradient-to-t from-black/25 to-transparent" />
                  {showLabel(k.midi) && (
                    <span className="pointer-events-none absolute inset-x-0 bottom-2 text-center text-[10px] font-semibold text-neutral-700">
                      {midiToNoteName(k.midi)}
                    </span>
                  )}
                </div>
              ))}
            </div>

            {blackKeys.map((k) => {
              const range = xRangeForMidi(k.midi)
              return (
                <div
                  key={k.midi}
                  onPointerDown={handlePointerDown(k.midi)}
                  onPointerUp={handlePointerUp}
                  onPointerCancel={handlePointerUp}
                  className="absolute top-0 cursor-pointer touch-none select-none overflow-hidden rounded-b-lg shadow-[0_4px_8px_rgba(0,0,0,0.5)] transition-[background] duration-75"
                  style={{
                    left: range.left,
                    width: range.width,
                    height: `${KEYBOARD_HEIGHT_PX * BLACK_HEIGHT_RATIO}px`,
                    background: activeNotes.has(k.midi)
                      ? "linear-gradient(to bottom, #ff4fbd 0%, #d10070 100%)"
                      : "linear-gradient(to bottom, #2a2a2a 0%, #0a0a0a 70%, #1a1a1a 100%)",
                  }}
                >
                  {/* Highlight stripe along the top */}
                  <div className="pointer-events-none absolute inset-x-1 top-0.5 h-px rounded-full bg-white/30" />
                  {/* Side bevel */}
                  <div className="pointer-events-none absolute inset-y-0 left-0 w-px bg-white/10" />
                  <div className="pointer-events-none absolute inset-y-0 right-0 w-px bg-black/60" />
                  {/* Bottom face shading */}
                  <div className="pointer-events-none absolute inset-x-0 bottom-0 h-2 bg-gradient-to-t from-white/15 to-transparent" />
                </div>
              )
            })}

            {/* Key-reactive light bleed: radial bloom centered on each pressed key,
                spilling onto neighboring whites + blacks via screen blend. */}
            <div
              className="pointer-events-none absolute inset-0"
              style={{ mixBlendMode: "screen" }}
            >
              {Array.from(activeNotes).map((m) => {
                const cx = xCenterPctForMidi(m)
                const color = PALETTE[m % PALETTE.length]
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

            {/* Soft top-edge bloom that intensifies with active notes */}
            {activeNotes.size > 0 && (
              <div
                className="pointer-events-none absolute inset-x-0 top-0 h-8 opacity-90"
                style={{
                  background: `linear-gradient(to bottom, ${HOT_PINK}66 0%, transparent 100%)`,
                  filter: "blur(6px)",
                  mixBlendMode: "screen",
                }}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
