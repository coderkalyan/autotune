import { ChevronLeft } from "lucide-react"
import { Button } from "@/components/ui/button"
import type { AppScreen } from "@/types"

interface Props {
  onNavigate: (screen: AppScreen) => void
}

export function BackButton({ onNavigate }: Props) {
  return (
    <Button variant="ghost" size="sm" onClick={() => onNavigate({ screen: "splash" })}>
      <ChevronLeft data-icon="inline-start" />
      Back
    </Button>
  )
}
