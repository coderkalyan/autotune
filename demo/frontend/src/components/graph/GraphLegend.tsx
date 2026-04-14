import { Badge } from "@/components/ui/badge"

interface Props {
  showTarget?: boolean
}

export function GraphLegend({ showTarget = false }: Props) {
  return (
    <div className="flex items-center gap-2">
      <Badge variant="outline" style={{ borderColor: "var(--chart-1)", color: "var(--chart-1)" }}>
        Detected
      </Badge>
      <Badge variant="outline" style={{ borderColor: "var(--chart-2)", color: "var(--chart-2)" }}>
        Corrected
      </Badge>
      {showTarget && (
        <Badge variant="outline" style={{ borderColor: "var(--chart-4)", color: "var(--chart-4)" }}>
          Target Vocal
        </Badge>
      )}
    </div>
  )
}
