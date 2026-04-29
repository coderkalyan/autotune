import { useMemo } from "react"
import type { LyricLine, LyricWord } from "@/types"

interface Props {
  lines: LyricLine[]
  positionMs: number | null
}

export function KaraokeLyrics({ lines, positionMs }: Props) {
  const pos = positionMs ?? 0

  const { active, next } = useMemo(() => {
    let idx = -1
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].timestamp_ms <= pos) idx = i
      else break
    }
    return {
      active: idx >= 0 ? lines[idx] : lines[0] ?? null,
      next: idx + 1 < lines.length ? lines[idx + 1] : null,
    }
  }, [lines, pos])

  return (
    <div className="relative z-10 flex flex-1 flex-col items-center justify-center gap-6 px-8 text-center">
      {active && <ActiveLine line={active} positionMs={pos} />}
      {next && (
        <p className="max-w-4xl text-2xl font-medium leading-snug text-muted-foreground/55">
          {next.text}
        </p>
      )}
    </div>
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
