import { useMemo } from "react"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  ResponsiveContainer,
} from "recharts"
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import type { FrequencyPoint } from "@/hooks/useWebSocket"

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

function hzToNote(hz: number): string {
  const midi = Math.round(12 * Math.log2(hz / 440) + 69)
  const name = NOTE_NAMES[((midi % 12) + 12) % 12]
  const octave = Math.floor(midi / 12) - 1
  return `${name}${octave}`
}

const chartConfig = {
  hz: { label: "Frequency (Hz)", color: "hsl(var(--chart-1))" },
}

export function FrequencyChart({ points }: { points: FrequencyPoint[] }) {
  const now = Date.now()

  const data = useMemo(
    () =>
      points.map((p) => ({
        t: ((p.ts - now) / 1000).toFixed(1),
        hz: Math.round(p.hz * 10) / 10,
      })),
    [points] // eslint-disable-line react-hooks/exhaustive-deps
  )

  const latest = points.at(-1)

  return (
    <Card className="h-full flex flex-col">
      <CardHeader className="flex flex-row items-center justify-between shrink-0">
        <CardTitle>Detected Frequency</CardTitle>
        {latest ? (
          <div className="text-right">
            <div className="text-3xl font-mono font-bold">
              {latest.hz.toFixed(1)} Hz
            </div>
            <div className="text-lg text-muted-foreground">
              {hzToNote(latest.hz)}
            </div>
          </div>
        ) : (
          <div className="text-sm text-muted-foreground">Waiting for data…</div>
        )}
      </CardHeader>
      <CardContent className="flex-1 min-h-0">
        <ChartContainer config={chartConfig} className="h-full w-full">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis
                dataKey="t"
                label={{ value: "seconds", position: "insideBottom", offset: -4 }}
              />
              <YAxis
                scale="log"
                domain={[80, 1200]}
                tickFormatter={(v: number) => `${v}`}
                label={{ value: "Hz", angle: -90, position: "insideLeft" }}
              />
              <ChartTooltip content={<ChartTooltipContent />} />
              <Line
                type="monotone"
                dataKey="hz"
                dot={false}
                strokeWidth={2}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </ChartContainer>
      </CardContent>
    </Card>
  )
}
