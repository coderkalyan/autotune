import { useEffect, useRef, useState } from "react"

interface Props {
  quality: number | null
}

function qualityBand(q: number | null): number {
  if (q === null) return -1
  if (q < 0.34) return 0
  if (q < 0.67) return 1
  return 2
}

export function PulsingBorder({ quality }: Props) {
  const [flashKey, setFlashKey] = useState<number | null>(null)
  const prevBandRef = useRef<number>(qualityBand(quality))

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

    const band = qualityBand(quality)
    if (band !== prevBandRef.current) {
      prevBandRef.current = band
      setFlashKey((k) => (k === null ? 0 : k + 1))
    }
  }, [quality])

  return (
    <div className="pointer-events-none fixed inset-0 z-20">
      <div className="karaoke-border-pulse absolute inset-0" />
      {flashKey !== null && (
        <div key={flashKey} className="karaoke-border-flash absolute inset-0" />
      )}
    </div>
  )
}
