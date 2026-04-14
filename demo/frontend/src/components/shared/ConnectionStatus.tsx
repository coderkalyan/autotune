import { cn } from "@/lib/utils"

interface Props {
  connected: boolean
}

export function ConnectionStatus({ connected }: Props) {
  return (
    <div className="flex items-center gap-2">
      <div
        className={cn(
          "size-2 rounded-full transition-colors duration-500",
          connected ? "bg-emerald-500 shadow-[0_0_6px_theme(colors.emerald.500)]" : "bg-zinc-600",
        )}
      />
      <span className="text-xs text-muted-foreground">{connected ? "Live" : "Offline"}</span>
    </div>
  )
}
