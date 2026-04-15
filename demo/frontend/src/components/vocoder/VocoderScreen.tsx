import { Separator } from "@/components/ui/separator"
import { BackButton } from "@/components/shared/BackButton"
import { SystemStatus } from "@/components/shared/SystemStatus"
import { VocoderGraph } from "./VocoderGraph"
import type { AppScreen, PitchReading } from "@/types"

interface Props {
  onNavigate: (screen: AppScreen) => void
  latest: PitchReading | null
  connected: boolean
}

export function VocoderScreen({ onNavigate, latest, connected }: Props) {
  return (
    <div className="flex size-full flex-col">
      {/* Top bar */}
      <div className="flex shrink-0 items-center px-4 py-2">
        <div className="flex flex-1 justify-start">
          <BackButton onNavigate={onNavigate} />
        </div>
        <h1 className="text-lg font-semibold">Vocoder</h1>
        <div className="flex flex-1 justify-end">
          <SystemStatus connected={connected} latest={latest} />
        </div>
      </div>

      <Separator />

      {/* Frequency envelope graph */}
      <div className="min-h-0 flex-1 p-4">
        <VocoderGraph vocodeBands={latest?.vocode_bands ?? null} />
      </div>
    </div>
  )
}
