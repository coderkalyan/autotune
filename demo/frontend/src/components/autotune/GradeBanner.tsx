import { useEffect, useRef, useState } from "react"

export type GradePhase = "preroll" | "get_ready" | "active" | "postroll"

interface Props {
  phase: GradePhase
  positionMs: number
  gradeStartMs: number
  gradeEndMs: number
}

export const PREROLL_LEAD_MS = 3000
export const POSTROLL_BANNER_MS = 3000
const FADE_MS = 300
const GET_READY_LABEL = "Get Ready"
const POSTROLL_LABEL = "Nice work"

export function GradeBanner({ phase, positionMs, gradeStartMs, gradeEndMs }: Props) {
  // Postroll banner: fade in on edge, hold for POSTROLL_BANNER_MS, fade out,
  // then unmount so the lyric strip resumes for the rest of the song.
  const [postrollVisible, setPostrollVisible] = useState(false)
  const [postrollFading, setPostrollFading] = useState(false)
  const lastPhaseRef = useRef<GradePhase | null>(null)
  const fadeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const hideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const prev = lastPhaseRef.current
    lastPhaseRef.current = phase
    if (phase === "postroll" && prev !== "postroll") {
      if (fadeTimerRef.current) clearTimeout(fadeTimerRef.current)
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current)
      setPostrollVisible(true)
      setPostrollFading(false)
      fadeTimerRef.current = setTimeout(() => {
        setPostrollFading(true)
        hideTimerRef.current = setTimeout(() => {
          setPostrollVisible(false)
          setPostrollFading(false)
        }, FADE_MS)
      }, POSTROLL_BANNER_MS)
    }
    if (phase !== "postroll" && prev === "postroll") {
      if (fadeTimerRef.current) clearTimeout(fadeTimerRef.current)
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current)
      setPostrollVisible(false)
      setPostrollFading(false)
    }
  }, [phase])

  useEffect(() => {
    return () => {
      if (fadeTimerRef.current) clearTimeout(fadeTimerRef.current)
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current)
    }
  }, [])

  if (phase === "get_ready") {
    const msUntilStart = Math.max(0, gradeStartMs - positionMs)
    const fillPct = Math.max(
      0,
      Math.min(100, ((PREROLL_LEAD_MS - msUntilStart) / PREROLL_LEAD_MS) * 100),
    )
    return (
      <BannerSlot>
        <FilledLabel label={GET_READY_LABEL} fillPct={fillPct} />
      </BannerSlot>
    )
  }

  if (postrollVisible) {
    void gradeEndMs
    return (
      <BannerSlot>
        <div
          className="transition-opacity duration-300"
          style={{ opacity: postrollFading ? 0 : 1 }}
        >
          <FilledLabel label={POSTROLL_LABEL} fillPct={100} />
        </div>
      </BannerSlot>
    )
  }

  return null
}

function BannerSlot({ children }: { children: React.ReactNode }) {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-20 flex justify-center px-8 pt-6">
      {children}
    </div>
  )
}

function FilledLabel({ label, fillPct }: { label: string; fillPct: number }) {
  return (
    <p
      className="text-5xl font-bold leading-tight tracking-tight"
      role="status"
      aria-label={label}
    >
      <span className="relative inline-block">
        <span className="text-foreground/35">{label}</span>
        <span
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 text-primary"
          style={{ clipPath: `inset(0 ${100 - fillPct}% 0 0)` }}
        >
          {label}
        </span>
      </span>
    </p>
  )
}
