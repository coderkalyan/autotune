import { Area, AreaChart, XAxis, YAxis } from "recharts"
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart"

const N_BANDS = 32
const F_LO = 300
const F_HI = 8000

// Pre-compute log-spaced center frequencies for each band
const BAND_FREQS: number[] = Array.from({ length: N_BANDS }, (_, i) =>
  F_LO * (F_HI / F_LO) ** (i / (N_BANDS - 1)),
)

// X-axis tick positions (band indices closest to key frequencies)
const KEY_FREQS = [300, 550, 800, 1000, 2000, 4000, 8000]
const KEY_TICKS = KEY_FREQS.map((f) =>
  BAND_FREQS.reduce(
    (best, freq, i) =>
      Math.abs(freq - f) < Math.abs(BAND_FREQS[best] - f) ? i : best,
    0,
  ),
)

function formatFreq(hz: number): string {
  return hz >= 1000 ? `${(hz / 1000).toFixed(0)}k` : `${Math.round(hz)}`
}

const chartConfig = {
  amplitude: { label: "Amplitude", color: "var(--chart-3)" },
} satisfies ChartConfig

interface Props {
  vocodeBands: number[] | null
}

export function VocoderGraph({ vocodeBands }: Props) {
  const data = BAND_FREQS.map((freq, i) => ({
    band: i,
    freq,
    amplitude: vocodeBands ? Math.max(0, vocodeBands[i]) : 0,
  }))

  return (
    <ChartContainer config={chartConfig} className="h-full w-full">
      <AreaChart data={data} margin={{ top: 16, right: 16, bottom: 8, left: 8 }}>
        <defs>
          <linearGradient id="vocoderFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="var(--chart-3)" stopOpacity={0.6} />
            <stop offset="95%" stopColor="var(--chart-3)" stopOpacity={0.05} />
          </linearGradient>
        </defs>
        <XAxis
          dataKey="band"
          type="number"
          domain={[0, N_BANDS - 1]}
          ticks={KEY_TICKS}
          tickFormatter={(i: number) => formatFreq(BAND_FREQS[i])}
          tick={{ fontSize: 11 }}
          axisLine={{ stroke: "var(--border)" }}
          tickLine={false}
          label={{ value: "Frequency (Hz)", position: "insideBottom", offset: -4, fontSize: 11, fill: "var(--muted-foreground)" }}
        />
        <YAxis
          domain={[0, "auto"]}
          tick={{ fontSize: 11 }}
          axisLine={{ stroke: "var(--border)" }}
          tickLine={false}
          width={48}
          label={{ value: "Amplitude", angle: -90, position: "insideLeft", fontSize: 11, fill: "var(--muted-foreground)" }}
        />
        <ChartTooltip
          content={
            <ChartTooltipContent
              labelFormatter={(_, payload) => {
                const item = payload?.[0]?.payload as { freq: number } | undefined
                return item ? `${item.freq.toFixed(0)} Hz` : ""
              }}
              formatter={(value) =>
                typeof value === "number" ? value.toFixed(4) : String(value)
              }
            />
          }
        />
        <Area
          dataKey="amplitude"
          type="monotone"
          stroke="var(--color-amplitude)"
          strokeWidth={2}
          fill="url(#vocoderFill)"
          dot={false}
          isAnimationActive={false}
        />
      </AreaChart>
    </ChartContainer>
  )
}
