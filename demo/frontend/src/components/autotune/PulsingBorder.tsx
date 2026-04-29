import { useEffect } from "react"

interface Props {
  quality: number | null
}

export function PulsingBorder({ quality }: Props) {
  useEffect(() => {
    const root = document.documentElement
    let color: string
    if (quality === null) {
      color = "oklch(0.5 0.02 0 / 0.18)"
    } else {
      const q = Math.max(0, Math.min(1, quality))
      const hue = 27 + 118 * q
      color = `oklch(0.72 0.18 ${hue} / 0.55)`
    }
    root.style.setProperty("--karaoke-border", color)
  }, [quality])

  return (
    <div className="karaoke-border-pulse pointer-events-none fixed inset-0 z-20" />
  )
}
