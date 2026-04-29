import { useEffect, useMemo, useRef, useState } from "react"
import type { LyricLine, LyricWord } from "@/types"

interface Props {
  lines: LyricLine[]
  positionMs: number | null
}

const GAP_GRACE_MS = 600
const COUNTDOWN_MIN_GAP_MS = 3000
const DOTS_COUNT = 3
const DOT_WINDOW_FRAC = 0.55
const BREATH_PERIOD_S = 4.6
const BREATH_AMP = 0.06

const ANIM_DURATION = 300
const ANIM_IN: React.CSSProperties = {
  animation: `lyric-line-in ${ANIM_DURATION}ms ease both`,
}
const ANIM_OUT: React.CSSProperties = {
  animation: `lyric-line-out ${ANIM_DURATION}ms ease both`,
}

type SlotContent =
  | { kind: "line"; line: LyricLine; positionMs: number }
  | { kind: "countdown"; gapProgress: number; positionMs: number }
  | null

function slotKey(s: SlotContent): string {
  if (!s) return "empty"
  if (s.kind === "countdown") return "countdown"
  return `line:${s.line.timestamp_ms}`
}

export function KaraokeLyrics({ lines, positionMs }: Props) {
  const pos = positionMs ?? 0

  const { current, upcoming } = useMemo(() => {
    let idx = -1
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].timestamp_ms <= pos) idx = i
      else break
    }
    return {
      current: idx >= 0 ? lines[idx] : null,
      upcoming: idx + 1 < lines.length ? lines[idx + 1] : null,
    }
  }, [lines, pos])

  const currentEnd = current ? lastWordEnd(current) : 0
  const upcomingStart = upcoming ? upcoming.timestamp_ms : Infinity
  const gapStartMs = current ? currentEnd : 0
  const fullGapMs = upcoming ? upcomingStart - gapStartMs : 0
  const msUntilLyric = upcoming ? upcomingStart - pos : Infinity
  const inGap = !current || pos > currentEnd + GAP_GRACE_MS
  const gapProgress =
    fullGapMs > 0
      ? Math.max(0, Math.min(1, (pos - gapStartMs) / fullGapMs))
      : 0

  const showCountdown =
    upcoming != null &&
    inGap &&
    fullGapMs > COUNTDOWN_MIN_GAP_MS &&
    msUntilLyric > 0

  const bigLine = current ?? upcoming

  const slot: SlotContent = showCountdown
    ? { kind: "countdown", gapProgress, positionMs: pos }
    : bigLine
      ? { kind: "line", line: bigLine, positionMs: pos }
      : null

  const key = slotKey(slot)
  const slotRef = useRef<SlotContent>(slot)
  slotRef.current = slot
  const prevSlotRef = useRef<SlotContent>(slot)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const [exiting, setExiting] = useState<SlotContent>(null)
  const [transitioning, setTransitioning] = useState(false)

  useEffect(() => {
    const prev = prevSlotRef.current
    const next = slotRef.current
    if (slotKey(prev) === slotKey(next)) return
    prevSlotRef.current = next
    if (timerRef.current) clearTimeout(timerRef.current)
    setExiting(prev)
    setTransitioning(true)
    timerRef.current = setTimeout(() => {
      setExiting(null)
      setTransitioning(false)
    }, ANIM_DURATION)
  }, [key])

  return (
    <div className="relative z-10 flex flex-1 flex-col items-center justify-center px-8 text-center">
      <div className="relative w-full overflow-hidden min-h-[9rem] flex items-center justify-center">
        <div
          className="w-full flex items-center justify-center"
          style={transitioning ? ANIM_IN : undefined}
        >
          <SlotView slot={slot} />
        </div>
        {exiting && (
          <div
            className="absolute inset-0 flex items-center justify-center"
            style={ANIM_OUT}
          >
            <SlotView slot={exiting} />
          </div>
        )}
      </div>
    </div>
  )
}

function SlotView({ slot }: { slot: SlotContent }) {
  if (!slot) return null
  if (slot.kind === "countdown") {
    return (
      <CountdownDots
        gapProgress={slot.gapProgress}
        positionMs={slot.positionMs}
      />
    )
  }
  return <ActiveLine line={slot.line} positionMs={slot.positionMs} />
}

function lastWordEnd(line: LyricLine): number {
  const ws = line.words
  if (ws && ws.length > 0) {
    const last = ws[ws.length - 1]
    return last.end_ms ?? last.timestamp_ms + 600
  }
  return line.timestamp_ms + 5000
}

function CountdownDots({
  gapProgress,
  positionMs,
}: {
  gapProgress: number
  positionMs: number
}) {
  const stagger = (1 - DOT_WINDOW_FRAC) / (DOTS_COUNT - 1)
  const breathT = positionMs / 1000
  const omega = (2 * Math.PI) / BREATH_PERIOD_S

  return (
    <div
      className="flex items-center justify-center gap-6"
      role="status"
      aria-label="Instrumental break"
    >
      {Array.from({ length: DOTS_COUNT }).map((_, i) => {
        const windowStart = i * stagger
        const local = (gapProgress - windowStart) / DOT_WINDOW_FRAC
        const t = Math.max(0, Math.min(1, local))
        const eased = springRiseToPeak(t)

        const breath = Math.sin(breathT * omega + i * 2.05)
        const breathFactor = 0.4 + 0.6 * eased
        const breathDamp =
          1 - Math.max(0, Math.min(1, (gapProgress - 0.92) / 0.08))
        const scale =
          0.5 + 0.7 * eased + BREATH_AMP * breathFactor * breath * breathDamp
        const opacity =
          0.25 +
          0.75 * Math.max(0, Math.min(1, eased + 0.04 * breath * breathDamp))

        return (
          <span
            key={i}
            className="block h-5 w-5 rounded-full bg-primary"
            style={{
              transform: `scale(${scale})`,
              opacity,
              transition: "transform 90ms linear, opacity 90ms linear",
            }}
          />
        )
      })}
    </div>
  )
}

function springRiseToPeak(t: number): number {
  if (t <= 0) return 0
  const c1 = 1.70158
  const c3 = c1 + 1
  const u = t * 0.58
  return 1 + c3 * Math.pow(u - 1, 3) + c1 * Math.pow(u - 1, 2)
}

function ActiveLine({ line, positionMs }: { line: LyricLine; positionMs: number }) {
  const words = line.words

  if (!words || words.length === 0) {
    return (
      <p className="max-w-5xl text-5xl font-bold leading-tight tracking-tight text-primary">
        {line.text}
      </p>
    )
  }

  return (
    <p className="flex max-w-5xl flex-wrap items-baseline justify-center gap-x-3 gap-y-2 text-5xl font-bold leading-tight tracking-tight">
      {words.map((w, i) => (
        <Word key={i} word={w} nextStart={words[i + 1]?.timestamp_ms ?? null} positionMs={positionMs} />
      ))}
    </p>
  )
}

function Word({
  word,
  nextStart,
  positionMs,
}: {
  word: LyricWord
  nextStart: number | null
  positionMs: number
}) {
  const end = word.end_ms ?? nextStart ?? word.timestamp_ms + 600
  const dur = Math.max(end - word.timestamp_ms, 100)
  const fillPct = Math.max(0, Math.min(100, ((positionMs - word.timestamp_ms) / dur) * 100))

  return (
    <span className="relative inline-block">
      <span className="text-foreground/35">{word.text}</span>
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 text-primary"
        style={{ clipPath: `inset(0 ${100 - fillPct}% 0 0)` }}
      >
        {word.text}
      </span>
    </span>
  )
}
