import { useEffect, useRef, useState } from "react"
import { Star } from "lucide-react"

interface Props {
  score: number | null      // 0..1
  combo: number | null
  stars: number | null      // 0..5
}

const COMBO_MILESTONES = [10, 25, 50, 100]
const SCORE_TWEEN_RATE = 6.0  // higher = snappier; per-second exponential ease

export function StatusRow({ score, combo, stars }: Props) {
  const target = score ?? 0
  const [displayScore, setDisplayScore] = useState(0)
  const rafRef = useRef<number | null>(null)
  const lastTsRef = useRef<number | null>(null)

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
  const filledStars = Math.max(0, Math.min(stars ?? 0, 5))

  return (
    <div className="relative z-10 flex shrink-0 items-center justify-between gap-4 border-t border-border/60 px-6 py-3">
      <div className="font-mono text-2xl font-semibold tabular-nums w-20">
        {pct}%
      </div>
      <div className="flex items-center gap-1.5">
        {[0, 1, 2, 3, 4].map((i) => (
          <Star
            key={i}
            className={
              "h-6 w-6 transition-colors " +
              (i < filledStars
                ? "fill-primary stroke-primary"
                : "stroke-muted-foreground/30")
            }
          />
        ))}
      </div>
      <div
        className={
          "w-20 text-right font-mono text-base tabular-nums transition-transform " +
          (flash ? "scale-125 text-primary" : "text-muted-foreground")
        }
      >
        {(combo ?? 0) > 0 ? `×${combo}` : ""}
      </div>
    </div>
  )
}
