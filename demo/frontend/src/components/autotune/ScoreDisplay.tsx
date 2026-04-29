import { useEffect, useRef, useState } from "react"

interface Props {
  score: number | null      // 0..1
  combo: number | null
  bestCombo: number | null
}

const COMBO_BAR_MAX = 25
const COMBO_MILESTONES = [10, 25, 50, 100]
const SCORE_TWEEN_RATE = 6.0  // higher = snappier; per-second exponential ease

export function ScoreDisplay({ score, combo, bestCombo }: Props) {
  const target = score ?? 0
  const [displayScore, setDisplayScore] = useState(0)
  const rafRef = useRef<number | null>(null)
  const lastTsRef = useRef<number | null>(null)

  // Smooth score tween toward target.
  useEffect(() => {
    function step(ts: number) {
      const last = lastTsRef.current ?? ts
      const dt = (ts - last) / 1000
      lastTsRef.current = ts
      setDisplayScore((curr) => {
        const k = 1 - Math.exp(-SCORE_TWEEN_RATE * dt)
        const next = curr + (target - curr) * k
        return Math.abs(next - target) < 1e-4 ? target : next
      })
      rafRef.current = requestAnimationFrame(step)
    }
    rafRef.current = requestAnimationFrame(step)
    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
      rafRef.current = null
      lastTsRef.current = null
    }
  }, [target])

  // Combo milestone flash.
  const prevComboRef = useRef(0)
  const [flash, setFlash] = useState(false)
  useEffect(() => {
    const now = combo ?? 0
    const prev = prevComboRef.current
    const crossed = COMBO_MILESTONES.some((m) => prev < m && now >= m)
    prevComboRef.current = now
    if (crossed) {
      setFlash(true)
      const t = setTimeout(() => setFlash(false), 600)
      return () => clearTimeout(t)
    }
  }, [combo])

  const pct = Math.round(displayScore * 100)
  const comboFill = Math.min((combo ?? 0) / COMBO_BAR_MAX, 1)

  return (
    <div className="shrink-0 flex items-center gap-3 px-4 py-1.5 border-b border-border/60">
      {/* Combo bar */}
      <div
        className={
          "relative h-1.5 flex-1 overflow-hidden rounded-full bg-muted " +
          (flash ? "ring-2 ring-primary/60 transition-all" : "")
        }
      >
        <div
          className="absolute inset-y-0 left-0 rounded-full bg-primary transition-[width] duration-150 ease-out"
          style={{ width: `${comboFill * 100}%` }}
        />
      </div>

      {/* Combo counter */}
      <div className="font-mono text-xs text-muted-foreground tabular-nums w-16 text-right">
        {(combo ?? 0) > 0 ? `${combo}× combo` : ""}
        {bestCombo !== null && bestCombo > 0 && (combo ?? 0) === 0 ? `best ${bestCombo}` : ""}
      </div>

      {/* Score */}
      <div className="font-mono text-base font-semibold tabular-nums w-14 text-right">
        {pct}%
      </div>
    </div>
  )
}
