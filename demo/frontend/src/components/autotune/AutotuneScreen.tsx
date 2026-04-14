import { Separator } from "@/components/ui/separator"
import { BackButton } from "@/components/shared/BackButton"
import { ConnectionStatus } from "@/components/shared/ConnectionStatus"
import { FreeModeView } from "./FreeModeView"
import { SubModeToggle } from "./SubModeToggle"
import type { AppScreen, PitchReading } from "@/types"

interface Props {
  screenState: Extract<AppScreen, { screen: "autotune" }>
  onNavigate: (screen: AppScreen) => void
  readings: PitchReading[]
  latest: PitchReading | null
  connected: boolean
}

export function AutotuneScreen({ screenState, onNavigate, readings, latest, connected }: Props) {
  const { subMode, selectedSong } = screenState

  function handleSubMode(next: "free" | "sing-along") {
    onNavigate({ screen: "autotune", subMode: next, selectedSong })
  }

  return (
    <div className="flex size-full flex-col">
      {/* Top bar */}
      <div className="flex shrink-0 items-center px-4 py-2">
        <div className="flex flex-1 justify-start">
          <BackButton onNavigate={onNavigate} />
        </div>
        <SubModeToggle value={subMode} onValueChange={handleSubMode} />
        <div className="flex flex-1 justify-end">
          <ConnectionStatus connected={connected} />
        </div>
      </div>

      <Separator />

      {/* Content */}
      <div className="min-h-0 flex-1">
        {subMode === "free" && (
          <FreeModeView readings={readings} latest={latest} />
        )}
        {subMode === "sing-along" && (
          <div className="flex size-full items-center justify-center text-muted-foreground">
            Sing Along — coming in next step
          </div>
        )}
      </div>
    </div>
  )
}
