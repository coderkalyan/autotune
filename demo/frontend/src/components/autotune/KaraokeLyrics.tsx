import { useEffect, useMemo, useRef, useState } from "react"
import type { LyricLine, LyricWord } from "@/types"

interface Props {
  lines: LyricLine[]
  positionMs: number | null
}

const GAP_GRACE_MS = 600
const COUNTDOWN_MIN_GAP_MS = 3000    // gap >3s => 3/2/1 countdown
const GET_READY_MIN_GAP_MS = 5000    // gap >5s => Get Ready before countdown
const COUNTDOWN_LEAD_MS = 3000       // ms before lyric where digits 3/2/1 take over
const DIGIT_FILL_MS = 1000           // each digit fills over this much time
const COUNTDOWN_DIGITS = ["3", "2", "1"] as const
const GET_READY_LABEL = "Get Ready"

const ANIM_DURATION = 300
const ANIM_IN: React.CSSProperties = {
  animation: `lyric-line-in ${ANIM_DURATION}ms ease both`,
}
const ANIM_OUT: React.CSSProperties = {
  animation: `lyric-line-out ${ANIM_DURATION}ms ease both`,
}

type Slot =
  | { kind: "line"; line: LyricLine; positionMs: number }
  | { kind: "getReady"; fillPct: number }
  | { kind: "countdown"; msUntilLyric: number }
  | { kind: "preview"; line: LyricLine }
  | null

function slotKey(s: Slot): string {
  if (!s) return "empty"
  if (s.kind === "getReady") return "getReady"
  if (s.kind === "countdown") return "countdown"
  if (s.kind === "preview") return `preview:${s.line.timestamp_ms}`
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

  // Gap >5s: "Get Ready" fills left→right then swaps to "3 2 1" digits in the
  // final COUNTDOWN_LEAD_MS. Gap 3-5s: only the digits, no Get Ready.
  const inGapWithUpcoming = upcoming != null && inGap && msUntilLyric > 0
  const showCountdown =
    inGapWithUpcoming &&
    fullGapMs > COUNTDOWN_MIN_GAP_MS &&
    msUntilLyric <= COUNTDOWN_LEAD_MS
  const showGetReady =
    inGapWithUpcoming &&
    fullGapMs > GET_READY_MIN_GAP_MS &&
    msUntilLyric > COUNTDOWN_LEAD_MS

  // Get Ready fill window: from gap start (msUntilLyric=fullGapMs) to the
  // moment the digits take over (msUntilLyric=COUNTDOWN_LEAD_MS).
  const getReadyFillPct = showGetReady
    ? Math.max(
        0,
        Math.min(
          100,
          ((fullGapMs - msUntilLyric) /
            Math.max(1, fullGapMs - COUNTDOWN_LEAD_MS)) *
            100,
        ),
      )
    : 0

  // Big slot: countdown digits > Get Ready > current line > upcoming line.
  const bigSlot: Slot = showCountdown
    ? { kind: "countdown", msUntilLyric }
    : showGetReady
      ? { kind: "getReady", fillPct: getReadyFillPct }
      : current
        ? { kind: "line", line: current, positionMs: pos }
        : upcoming
          ? { kind: "line", line: upcoming, positionMs: pos }
          : null

  // Preview always shows next lyric when present (including during Get Ready
  // / countdown), unless the big slot itself is already that upcoming line.
  const bigShowsUpcoming =
    !showCountdown &&
    !showGetReady &&
    current == null &&
    upcoming != null
  const previewSlot: Slot =
    upcoming && !bigShowsUpcoming
      ? { kind: "preview", line: upcoming }
      : null

  return (
    <div className="relative z-10 flex flex-1 flex-col items-center justify-center gap-6 px-8 text-center">
      <AnimatedSlot slot={bigSlot} minHClass="min-h-[9rem]" />
      <AnimatedSlot slot={previewSlot} minHClass="min-h-[4rem]" />
    </div>
  )
}

function AnimatedSlot({
  slot,
  minHClass,
}: {
  slot: Slot
  minHClass: string
}) {
  const key = slotKey(slot)
  const slotRef = useRef<Slot>(slot)
  slotRef.current = slot
  const prevSlotRef = useRef<Slot>(slot)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const [exiting, setExiting] = useState<Slot>(null)
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
    <div
      className={`relative w-full overflow-hidden ${minHClass} flex items-center justify-center`}
    >
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
  )
}

function SlotView({ slot }: { slot: Slot }) {
  if (!slot) return null
  if (slot.kind === "countdown") {
    return <CountdownDigits msUntilLyric={slot.msUntilLyric} />
  }
  if (slot.kind === "getReady") {
    return <GetReadyLabel fillPct={slot.fillPct} />
  }
  if (slot.kind === "preview") {
    return <PreviewLine line={slot.line} />
  }
  return <ActiveLine line={slot.line} positionMs={slot.positionMs} />
}

function GetReadyLabel({ fillPct }: { fillPct: number }) {
  return (
    <p
      className="max-w-5xl text-5xl font-bold leading-tight tracking-tight"
      role="status"
      aria-label={GET_READY_LABEL}
    >
      <span className="relative inline-block">
        <span className="text-foreground/35">{GET_READY_LABEL}</span>
        <span
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 text-primary"
          style={{ clipPath: `inset(0 ${100 - fillPct}% 0 0)` }}
        >
          {GET_READY_LABEL}
        </span>
      </span>
    </p>
  )
}

function PreviewLine({ line }: { line: LyricLine }) {
  return (
    <p className="max-w-4xl text-2xl font-medium leading-snug text-muted-foreground/55">
      {line.text}
    </p>
  )
}

function lastWordEnd(line: LyricLine): number {
  const ws = line.words
  if (ws && ws.length > 0) {
    const last = ws[ws.length - 1]
    return last.end_ms ?? last.timestamp_ms + 600
  }
  return line.timestamp_ms + 5000
}

function CountdownDigits({ msUntilLyric }: { msUntilLyric: number }) {
  // Each digit fills over its own DIGIT_FILL_MS window:
  //   "3" fills from msUntilLyric=3000→2000
  //   "2" fills from 2000→1000
  //   "1" fills from 1000→0  (hits 100% exactly at lyric start)
  return (
    <p
      className="flex max-w-5xl items-baseline justify-center gap-x-8 text-5xl font-bold leading-tight tracking-tight tabular-nums"
      role="status"
      aria-label="Instrumental break"
    >
      {COUNTDOWN_DIGITS.map((label, i) => {
        const startMs = (COUNTDOWN_DIGITS.length - i) * DIGIT_FILL_MS
        const fillPct = Math.max(
          0,
          Math.min(100, ((startMs - msUntilLyric) / DIGIT_FILL_MS) * 100),
        )
        return (
          <span key={i} className="relative inline-block">
            <span className="text-foreground/35">{label}</span>
            <span
              aria-hidden="true"
              className="pointer-events-none absolute inset-0 text-primary"
              style={{ clipPath: `inset(0 ${100 - fillPct}% 0 0)` }}
            >
              {label}
            </span>
          </span>
        )
      })}
    </p>
  )
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
