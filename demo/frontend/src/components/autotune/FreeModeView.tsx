import { PitchGraph } from "@/components/graph/PitchGraph"
import type { PitchReading } from "@/types"

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

function hzToNoteName(hz: number): string {
  const midi = Math.round(12 * Math.log2(hz / 440) + 69)
  const octave = Math.floor(midi / 12) - 1
  return `${NOTE_NAMES[((midi % 12) + 12) % 12]}${octave}`
}

interface Props {
  readings: PitchReading[]
  latest: PitchReading | null
}

export function FreeModeView({ readings, latest }: Props) {
  const detectedHz = latest?.detected_hz ?? null
  const correctedHz = latest?.corrected_hz ?? null

  const noteName = correctedHz ? hzToNoteName(correctedHz) : null

  return (
    <div className="flex size-full flex-col gap-4 p-6">
      {/* Tuner strip */}
      <div className="flex shrink-0 items-end gap-6">
        <div className="flex flex-col leading-none">
          <span className="text-8xl font-bold tracking-tighter text-foreground">
            {noteName ?? "—"}
          </span>
        </div>
        <div className="mb-2 flex flex-col gap-1">
          {detectedHz !== null && (
            <span className="text-sm text-muted-foreground">
              Raw{" "}
              <span className="font-mono text-foreground">{detectedHz.toFixed(1)} Hz</span>
            </span>
          )}
          {correctedHz !== null && (
            <span className="text-sm text-muted-foreground">
              Corrected{" "}
              <span className="font-mono" style={{ color: "var(--chart-2)" }}>
                {correctedHz.toFixed(1)} Hz
              </span>
            </span>
          )}
        </div>
      </div>

      {/* Graph */}
      <div className="min-h-0 flex-1">
        <PitchGraph readings={readings} />
      </div>
    </div>
  )
}
