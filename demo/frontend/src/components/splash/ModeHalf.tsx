import { type LucideIcon } from "lucide-react"
import { cn } from "@/lib/utils"

interface Props {
  title: string
  description: string
  Icon: LucideIcon
  accentColor: string       // CSS color value for gradient + icon tint
  illustration: React.ReactNode
  onClick: () => void
  className?: string
}

export function ModeHalf({ title, description, Icon, accentColor, illustration, onClick, className }: Props) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "group relative flex flex-1 flex-col items-center justify-center overflow-hidden",
        "cursor-pointer border-0 bg-transparent",
        "focus-visible:outline-none",
        className,
      )}
    >
      {/* Radial gradient accent */}
      <div
        className="pointer-events-none absolute inset-0 opacity-20 transition-opacity duration-300 group-hover:opacity-35"
        style={{
          background: `radial-gradient(ellipse 60% 55% at 50% 60%, ${accentColor}, transparent)`,
        }}
      />

      {/* Subtle top-edge glow */}
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-px opacity-40"
        style={{ background: `linear-gradient(to right, transparent, ${accentColor}, transparent)` }}
      />

      {/* Background illustration */}
      <div className="pointer-events-none absolute inset-0 flex items-center justify-center opacity-5 transition-opacity duration-300 group-hover:opacity-10">
        {illustration}
      </div>

      {/* Content */}
      <div className="relative flex flex-col items-center gap-6 px-12 text-center">
        <div
          className="flex size-24 items-center justify-center rounded-full border border-white/10 backdrop-blur-sm transition-transform duration-300 group-hover:scale-110"
          style={{ background: `${accentColor}22` }}
        >
          <Icon
            className="size-12 transition-colors duration-300"
            style={{ color: accentColor }}
            strokeWidth={1.5}
          />
        </div>

        <div className="flex flex-col gap-3">
          <h2 className="text-5xl font-bold tracking-tight text-foreground">{title}</h2>
          <p className="max-w-xs text-base leading-relaxed text-muted-foreground">{description}</p>
        </div>
      </div>
    </button>
  )
}
