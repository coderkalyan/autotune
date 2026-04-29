import { useMemo } from "react"
import type { LyricLine, LyricWord } from "@/types"

interface Props {
  lines: LyricLine[]
  positionMs: number | null
}

// Dots replace the big-lyric slot during instrumental gaps. Tuned so short
// gaps between phrases keep the just-finished lyric visible (no flicker),
// while real instrumental breaks pace 3 dots across the full gap. Windows
// overlap so dots sequence smoothly (always one dot in motion), and a
// per-dot phase-offset breathing layer keeps them from feeling static.
const GAP_GRACE_MS = 600           // wait this long after current line ends before considering it a gap
const COUNTDOWN_MIN_GAP_MS = 3000  // only enter countdown mode when full gap is at least this long
const DOTS_COUNT = 3
const DOT_WINDOW_FRAC = 0.55       // each dot's grow span as a fraction of the full gap; >1/N → overlap
const BREATH_PERIOD_S = 4.6        // ambient breathing period (low freq = calm)
const BREATH_AMP = 0.06            // peak scale wobble from breathing

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
  // Gap pacing starts from the current line's end (or t=0 for pre-song) so
  // the first dot is already easing in by the time dots become visible.
  const gapStartMs = current ? currentEnd : 0
  const fullGapMs = upcoming ? upcomingStart - gapStartMs : 0
  const msUntilLyric = upcoming ? upcomingStart - pos : Infinity
  const inGap = !current || pos > currentEnd + GAP_GRACE_MS
  const gapProgress =
    fullGapMs > 0
      ? Math.max(0, Math.min(1, (pos - gapStartMs) / fullGapMs))
      : 0

  // Long instrumental break: dots take over the big slot and grow toward the
  // next lyric. Stays visible until the lyric actually starts.
  const showCountdown =
    upcoming != null &&
    inGap &&
    fullGapMs > COUNTDOWN_MIN_GAP_MS &&
    msUntilLyric > 0

  // Pre-song (no current yet), use upcoming as the big preview so the screen
  // isn't blank between dots and the first line.
  const bigLine = current ?? upcoming
  const previewLine = current && upcoming ? upcoming : null

  return (
    <div className="relative z-10 flex flex-1 flex-col items-center justify-center gap-6 px-8 text-center">
      {showCountdown ? (
        <CountdownDots gapProgress={gapProgress} positionMs={pos} />
      ) : (
        bigLine && <ActiveLine line={bigLine} positionMs={pos} />
      )}
      {!showCountdown && previewLine && (
        <p className="max-w-4xl text-2xl font-medium leading-snug text-muted-foreground/55">
          {previewLine.text}
        </p>
      )}
    </div>
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

function CountdownDots({
  gapProgress,
  positionMs,
}: {
  gapProgress: number
  positionMs: number
}) {
  // Stagger overlapping grow-windows so the visual is always advancing
  // (no robotic plateau between dots). Final dot lands at gapProgress=1.
  const stagger = (1 - DOT_WINDOW_FRAC) / (DOTS_COUNT - 1)
  // Time-driven breathing — uses the song clock so dots stay aligned with
  // the music, with a phase offset per dot for a natural out-of-sync wobble.
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

        // Ambient breathing: subtle pre-grow shimmer (40% amp), full amp once
        // the dot has bloomed. Phase-offset by 2.05 rad per dot. Damped to
        // zero in the last sliver so dots land cleanly at peak as the lyric
        // takes over (no late-arriving wobble fighting the handoff).
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

// easeOutBack stretched so its overshoot peak lands at t=1 (instead of t≈0.58
// for the raw curve). Monotonic rise → dot keeps growing right up to handoff,
// no perceived "settled" plateau between dot fully grown and lyric starting.
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
