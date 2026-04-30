import { Music2, Piano, Radio } from "lucide-react"
import type { AppScreen } from "@/types"
import { ModeHalf } from "./ModeHalf"

// Sine wave illustration for Autotune
function SineWaveIllustration() {
  return (
    <svg viewBox="0 0 600 300" className="w-full max-w-2xl" fill="none">
      {[0, 1, 2].map((i) => (
        <path
          key={i}
          d={`M${-60 + i * 20} 150 C${30 + i * 20} ${60 + i * 10}, ${120 + i * 20} ${240 - i * 10}, ${210 + i * 20} 150 S${390 + i * 20} ${60 + i * 10}, ${480 + i * 20} 150 S${660 + i * 20} ${240 - i * 10}, ${750 + i * 20} 150`}
          stroke="white"
          strokeWidth={3 - i * 0.8}
          opacity={1 - i * 0.3}
        />
      ))}
    </svg>
  )
}

// Stacked piano-key illustration for Synth
function PianoKeysIllustration() {
  return (
    <svg viewBox="0 0 600 300" className="w-full max-w-2xl" fill="none">
      {Array.from({ length: 9 }).map((_, i) => (
        <rect
          key={`w-${i}`}
          x={40 + i * 60}
          y={60}
          width={56}
          height={200}
          stroke="white"
          strokeWidth={1.5}
          opacity={0.6}
        />
      ))}
      {[0, 1, 3, 4, 5, 7, 8].map((i) => (
        <rect
          key={`b-${i}`}
          x={70 + i * 60}
          y={60}
          width={36}
          height={120}
          fill="white"
          opacity={0.35}
        />
      ))}
    </svg>
  )
}

// Concentric rings illustration for Vocoder
function ConcentricRingsIllustration() {
  return (
    <svg viewBox="0 0 400 400" className="w-full max-w-xl" fill="none">
      {[180, 140, 100, 65, 35].map((r, i) => (
        <circle
          key={r}
          cx="200"
          cy="200"
          r={r}
          stroke="white"
          strokeWidth={2 - i * 0.3}
          opacity={0.6 - i * 0.1}
        />
      ))}
      <circle cx="200" cy="200" r="12" fill="white" opacity="0.8" />
    </svg>
  )
}

interface Props {
  onNavigate: (screen: AppScreen) => void
}

export function SplashScreen({ onNavigate }: Props) {
  return (
    <div className="relative flex size-full bg-background">
      <ModeHalf
        title="Autotune"
        description="Pitch correction and real-time sing-along with scrolling pitch visualization"
        Icon={Music2}
        accentColor="#2dd4bf"
        illustration={<SineWaveIllustration />}
        onClick={() => onNavigate({ screen: "autotune", subMode: "free", selectedSong: null })}
      />

      {/* Center divider with title badge
      <div className="relative z-10 flex shrink-0 flex-col items-center justify-center">
        <Separator orientation="vertical" className="h-full" />
        <div className="absolute flex flex-col items-center gap-1.5 rounded-full border border-border bg-background px-5 py-3 shadow-lg">
          <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
            FPGA
          </span>
          <span className="text-sm font-bold text-foreground">Demo</span>
        </div>
      </div> */}

      <ModeHalf
        title="Vocoder"
        description="Real-time voice synthesis and spectral manipulation with FPGA-powered DSP"
        Icon={Radio}
        accentColor="#a78bfa"
        illustration={<ConcentricRingsIllustration />}
        onClick={() => onNavigate({ screen: "vocoder" })}
      />

      <ModeHalf
        title="Synth"
        description="Live MIDI keyboard visualization with rising notes and FPGA synthesis"
        Icon={Piano}
        accentColor="#f472b6"
        illustration={<PianoKeysIllustration />}
        onClick={() => onNavigate({ screen: "synth" })}
      />
    </div>
  )
}
