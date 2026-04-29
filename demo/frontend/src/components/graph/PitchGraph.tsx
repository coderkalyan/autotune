import { useMemo } from "react"
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

const chartConfig = {
  detected_hz: { label: "Detected", color: "var(--chart-1)" },
  corrected_hz: { label: "Corrected", color: "var(--chart-2)" },
} satisfies ChartConfig

interface Props {
  readings: PitchReading[]
}

export function PitchGraph({ readings }: Props) {
  const lastActiveHz = useMemo(() => {
    for (let i = readings.length - 1; i >= 0; i--) {
      const r = readings[i]
      const val = r.detected_held ?? r.detected_hz
      if (val !== null && val !== undefined) return val
    }
    return null
  }, [readings])

  const minTs = readings.length > 0 ? readings[0].timestamp_ms : 0
  const maxTs =
    readings.length > 0 ? readings[readings.length - 1].timestamp_ms : 1000
  const range = maxTs - minTs
  // Extend right edge so latest point sits at 85% of the visible window (15% empty on right)
  const domainMax = maxTs + range * (0.15 / 0.85)

  return (
    <div className="relative h-full w-full">
      {lastActiveHz !== null && (
        <div
          className="absolute top-2 z-10 flex items-baseline gap-1.5"
          style={{ left: 96 }}
        >
          <span
            className="font-mono text-sm font-semibold"
            style={{ color: "var(--chart-1)" }}
          >
            {hzToNoteName(lastActiveHz)}
          </span>
          <span className="font-mono text-xs text-muted-foreground">
            {lastActiveHz.toFixed(1)} Hz
          </span>
        </div>
      )}
      <ChartContainer config={chartConfig} className="h-full w-full">
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
            dataKey="detected_held"
            stroke="var(--chart-1)"
            strokeWidth={2}
            strokeDasharray="4 4"
            strokeOpacity={0.45}
            dot={false}
            isAnimationActive={false}
            connectNulls={true}
            legendType="none"
          />
          <Line
            dataKey="corrected_hz"
            stroke="var(--color-corrected_hz)"
            strokeWidth={2}
            dot={false}
            isAnimationActive={false}
            connectNulls={false}
          />
          <Line
            dataKey="corrected_held"
            stroke="var(--color-corrected_hz)"
            strokeWidth={2}
            strokeDasharray="4 4"
            strokeOpacity={0.45}
            dot={false}
            isAnimationActive={false}
            connectNulls={true}
            legendType="none"
          />
        </LineChart>
      </ChartContainer>
    </div>
  )
}
