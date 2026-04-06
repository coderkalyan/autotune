import { Badge } from "@/components/ui/badge"

export function SerialStatus({ connected }: { connected: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <Badge variant={connected ? "default" : "secondary"}>
        {connected ? "Connected" : "Disconnected"}
      </Badge>
      <span className="text-sm text-muted-foreground">UART 31250 baud</span>
    </div>
  )
}
