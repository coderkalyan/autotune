import { useEffect, useRef, useState } from "react"

const ROMAN_MAJOR = ["", "I", "ii", "iii", "IV", "V", "vi", "vii°"]
const ROMAN_MINOR = ["", "i", "ii°", "III", "iv", "v", "VI", "VII"]

interface Props {
  keyName: string
  chordState: number   // 1..7 (0 = none)
  minor: boolean
  melodyName: string
  harm1Name: string
  harm2Name: string
  primaryColor: string
  secondaryColor: string
}

export function ChordHud({
  keyName,
  chordState,
  minor,
  melodyName,
  harm1Name,
  harm2Name,
  primaryColor,
  secondaryColor,
}: Props) {
  const roman =
    chordState >= 1 && chordState <= 7
      ? (minor ? ROMAN_MINOR : ROMAN_MAJOR)[chordState]
      : "—"

  // Pulse on chord change.
  const [pulseId, setPulseId] = useState(0)
  const prevChord = useRef(chordState)
  useEffect(() => {
    if (prevChord.current !== chordState) {
      prevChord.current = chordState
      setPulseId((i) => i + 1)
    }
  }, [chordState])

  return (
    <div className="rounded-2xl border border-border bg-card/60 p-6 shadow-lg backdrop-blur">
      <div className="flex items-baseline justify-between">
        <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          Key
        </span>
        <span className="text-2xl font-bold text-foreground">{keyName || "—"}</span>
      </div>

      <div
        key={pulseId}
        className="my-4 flex items-center justify-center rounded-xl bg-accent/10 py-6 chord-pulse"
      >
        <span className="text-6xl font-black tracking-wide text-accent">{roman}</span>
      </div>

      <div className="grid grid-cols-3 gap-2">
        <NotePill label="Melody" name={melodyName} color={primaryColor} />
        <NotePill label="Harm 1" name={harm1Name} color={secondaryColor} />
        <NotePill label="Harm 2" name={harm2Name} color={secondaryColor} />
      </div>

      <style>{`
        .chord-pulse { animation: chordPulse 280ms ease-out; }
        @keyframes chordPulse {
          0% { transform: scale(0.96); filter: brightness(1.4); }
          60% { transform: scale(1.02); filter: brightness(1.15); }
          100% { transform: scale(1); filter: brightness(1); }
        }
      `}</style>
    </div>
  )
}

function NotePill({ label, name, color }: { label: string; name: string; color: string }) {
  return (
    <div
      className="flex flex-col items-center gap-0.5 rounded-lg px-3 py-3"
      style={{
        background: `color-mix(in srgb, ${color} 14%, transparent)`,
        border: `1px solid color-mix(in srgb, ${color} 35%, transparent)`,
      }}
    >
      <span className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
        {label}
      </span>
      <span className="text-2xl font-bold" style={{ color }}>
        {name || "—"}
      </span>
    </div>
  )
}
