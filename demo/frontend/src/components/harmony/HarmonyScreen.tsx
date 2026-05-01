import { useMemo } from "react"
import { Separator } from "@/components/ui/separator"
import { BackButton } from "@/components/shared/BackButton"
import { SystemStatus } from "@/components/shared/SystemStatus"
import {
  PianoKeyboard,
  type KeyHighlight,
} from "@/components/shared/PianoKeyboard"
import type { AppScreen, PitchReading } from "@/types"
import { PitchClassWheel } from "./PitchClassWheel"
import { ChordHud } from "./ChordHud"

const PRIMARY = "#ec4899" // pink-500: melody pops against the teal palette
const SECONDARY = "var(--chart-1)" // teal: harmony lines
const KEYBOARD_HEIGHT_PX = 180

interface Props {
  onNavigate: (screen: AppScreen) => void
  latest: PitchReading | null
  connected: boolean
}

export function HarmonyScreen({ onNavigate, latest, connected }: Props) {
  const melody = latest?.melody_midi ?? null
  const h1 = latest?.harm1_midi ?? null
  const h2 = latest?.harm2_midi ?? null
  const tonic = latest?.harm_tonic ?? 0
  const minor = latest?.harm_mode === 1
  const chord = latest?.chord_state ?? 0
  const inScale = latest?.in_scale === true

  const highlights = useMemo(() => {
    const m = new Map<number, KeyHighlight>()
    // Order matters: melody set last so it overrides if a harmony lands on the same key.
    if (h1 != null && h1 > 0) m.set(h1, { key: SECONDARY })
    if (h2 != null && h2 > 0) m.set(h2, { key: SECONDARY })
    if (melody != null && melody > 0) m.set(melody, { key: PRIMARY })
    return m
  }, [melody, h1, h2])

  const melodyPc = melody != null && melody > 0 ? melody % 12 : null
  const h1Pc = h1 != null && h1 > 0 ? h1 % 12 : null
  const h2Pc = h2 != null && h2 > 0 ? h2 % 12 : null

  return (
    <div className="flex size-full flex-col">
      <div className="flex shrink-0 items-center px-4 py-2">
        <div className="flex flex-1 justify-start">
          <BackButton onNavigate={onNavigate} />
        </div>
        <h1 className="text-lg font-semibold">Harmonize</h1>
        <div className="flex flex-1 justify-end">
          <SystemStatus connected={connected} latest={latest} />
        </div>
      </div>

      <Separator />

      <div className="flex min-h-0 flex-1 flex-col bg-gradient-to-b from-background to-muted/20 px-4 pb-6">
        {/* Top section: HUD + wheel side-by-side */}
        <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 py-4 md:grid-cols-2">
          <div className="flex items-center justify-center">
            <ChordHud
              keyName={latest?.harm_key_name ?? ""}
              chordState={chord}
              minor={minor}
              melodyName={latest?.melody_note_name ?? ""}
              harm1Name={latest?.harm1_note_name ?? ""}
              harm2Name={latest?.harm2_note_name ?? ""}
              primaryColor={PRIMARY}
              secondaryColor={SECONDARY}
            />
          </div>

          <div className="flex items-center justify-center rounded-2xl border border-border bg-card/40 p-4 shadow-lg backdrop-blur">
            <PitchClassWheel
              tonic={tonic}
              minor={minor}
              melodyPc={melodyPc}
              harm1Pc={h1Pc}
              harm2Pc={h2Pc}
              inScale={inScale}
              primaryColor={PRIMARY}
              secondaryColor={SECONDARY}
            />
          </div>
        </div>

        {/* Keyboard at the bottom */}
        <div
          className="relative shrink-0 rounded-2xl bg-neutral-900/60 p-2 shadow-[0_20px_60px_-20px_rgba(0,0,0,0.6)] ring-1 ring-white/5"
          style={{ height: `${KEYBOARD_HEIGHT_PX + 16}px` }}
        >
          <div
            className="pointer-events-none absolute inset-x-6 -top-3 h-3 rounded-full opacity-80 blur-md"
            style={{
              background: `linear-gradient(to right, transparent, ${PRIMARY}, transparent)`,
            }}
          />
          <PianoKeyboard
            highlights={highlights}
            heightPx={KEYBOARD_HEIGHT_PX}
          />
        </div>
      </div>
    </div>
  )
}
