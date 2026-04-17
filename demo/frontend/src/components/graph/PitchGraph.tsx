import { Line, LineChart, XAxis, YAxis } from "recharts"
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart"
import { PITCH_MAX_HZ, PITCH_MIN_HZ } from "@/config"
import type { PitchReading } from "@/types"

const NOTE_NAMES = [
  "C",
  "C#",
  "D",
  "D#",
  "E",
  "F",
  "F#",
  "G",
  "G#",
  "A",
  "A#",
  "B",
]

function hzToNoteName(hz: number): string {
  const midi = Math.round(12 * Math.log2(hz / 440) + 69)
  const octave = Math.floor(midi / 12) - 1
  return `${NOTE_NAMES[((midi % 12) + 12) % 12]}${octave}`
}

function formatYTick(hz: number): string {
  try {
    return `${hzToNoteName(hz)} · ${hz}`
  } catch {
    return `${hz}`
  }
}

const baseConfig = {
  detected_hz: { label: "Detected", color: "var(--chart-1)" },
  corrected_hz: { label: "Corrected", color: "var(--chart-2)" },
} satisfies ChartConfig

const withTargetConfig = {
  ...baseConfig,
  target_hz: { label: "Target Vocal", color: "var(--chart-4)" },
} satisfies ChartConfig

interface Props {
  readings: PitchReading[]
  showTarget?: boolean
}

export function PitchGraph({ readings, showTarget = false }: Props) {
  const config = showTarget ? withTargetConfig : baseConfig

  const minTs = readings.length > 0 ? readings[0].timestamp_ms : 0
  const maxTs =
    readings.length > 0 ? readings[readings.length - 1].timestamp_ms : 1000
  const range = maxTs - minTs
  // Extend right edge so latest point sits at 85% of the visible window (15% empty on right)
  const domainMax = maxTs + range * (0.15 / 0.85)

  return (
    <ChartContainer config={config} className="h-full w-full">
      <LineChart
        data={readings}
        margin={{ top: 8, right: 16, bottom: 8, left: 8 }}
      >
        <XAxis
          dataKey="timestamp_ms"
          type="number"
          domain={[minTs, domainMax]}
          scale="time"
          hide={false}
          tick={false}
          tickLine={false}
          axisLine={{ stroke: "var(--border)" }}
        />
        <YAxis
          scale="log"
          domain={[PITCH_MIN_HZ, PITCH_MAX_HZ]}
          allowDataOverflow={true}
          tickFormatter={formatYTick}
          tick={{ fontSize: 11 }}
          axisLine={{ stroke: "var(--border)" }}
          tickLine={false}
          width={88}
        />
        <ChartTooltip
          content={
            <ChartTooltipContent
              formatter={(value) =>
                value !== null ? `${(value as number).toFixed(1)} Hz` : "—"
              }
            />
          }
        />
        <ChartLegend content={<ChartLegendContent />} />
        <Line
          dataKey="detected_hz"
          stroke="var(--color-detected_hz)"
          strokeWidth={2}
          dot={false}
          isAnimationActive={false}
          connectNulls={false}
        />
        <Line
          dataKey="corrected_hz"
          stroke="var(--color-corrected_hz)"
          strokeWidth={2}
          dot={false}
          isAnimationActive={false}
          connectNulls={false}
        />
        {showTarget && (
          <Line
            dataKey="target_hz"
            stroke="var(--color-target_hz)"
            strokeWidth={2}
            strokeDasharray="6 3"
            dot={false}
            isAnimationActive={false}
            connectNulls={false}
          />
        )}
      </LineChart>
    </ChartContainer>
  )
}
