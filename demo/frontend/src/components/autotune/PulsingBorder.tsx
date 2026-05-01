import { useEffect } from "react"

interface Props {
  quality: number | null
}

export function PulsingBorder({ quality }: Props) {
  useEffect(() => {
    const root = document.documentElement
    let color: string
    let intensity: number
    if (quality === null) {
      color = "oklch(0.5 0.02 0 / 0.18)"
      intensity = 0.35
    } else {
      const q = Math.max(0, Math.min(1, quality))
      const hue = 27 + 118 * q
      color = `oklch(0.72 0.18 ${hue} / 0.55)`
      intensity = 0.55 + 0.45 * q
    }
    root.style.setProperty("--karaoke-border", color)
    root.style.setProperty("--karaoke-intensity", intensity.toFixed(3))
  }, [quality])

  return (
    <div className="pointer-events-none fixed inset-0 z-20">
      <div className="karaoke-border-pulse absolute inset-0" />
    </div>
  )
}
