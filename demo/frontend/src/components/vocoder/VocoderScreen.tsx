import { Radio } from "lucide-react"
import type { AppScreen } from "@/types"

interface Props {
  onNavigate: (screen: AppScreen) => void
}

export function VocoderScreen({ onNavigate }: Props) {
  return (
    <div className="flex size-full flex-col items-center justify-center gap-6">
      <Radio className="size-16 text-muted-foreground" strokeWidth={1.5} />
      <div className="flex flex-col items-center gap-2 text-center">
        <h2 className="text-3xl font-bold">Vocoder</h2>
        <p className="text-muted-foreground">Coming soon</p>
      </div>
      <button
        onClick={() => onNavigate({ screen: "splash" })}
        className="text-sm text-muted-foreground underline-offset-4 hover:underline"
      >
        Back to menu
      </button>
    </div>
  )
}
