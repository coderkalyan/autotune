const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const MAJOR_MASK = new Set([0, 2, 4, 5, 7, 9, 11])
const MINOR_MASK = new Set([0, 2, 3, 5, 7, 8, 10]) // natural minor

interface Props {
  tonic: number          // 0..11
  minor: boolean
  melodyPc: number | null
  harm1Pc: number | null
  harm2Pc: number | null
  inScale: boolean
  primaryColor: string
  secondaryColor: string
  size?: number
}

export function PitchClassWheel({
  tonic,
  minor,
  melodyPc,
  harm1Pc,
  harm2Pc,
  inScale,
  primaryColor,
  secondaryColor,
  size = 280,
}: Props) {
  const cx = size / 2
  const cy = size / 2
  const r = size * 0.42
  const mask = minor ? MINOR_MASK : MAJOR_MASK
  const t = tonic % 12

  // Build sounding-PC color map: melody PRIMARY wins on overlap.
  const sounding = new Map<number, string>()
  if (harm1Pc != null) sounding.set(harm1Pc, secondaryColor)
  if (harm2Pc != null) sounding.set(harm2Pc, secondaryColor)
  if (melodyPc != null) sounding.set(melodyPc, primaryColor)

  return (
    <svg viewBox={`0 0 ${size} ${size}`} className="w-full max-w-[300px] overflow-visible">
      {/* Background ring */}
      <circle cx={cx} cy={cy} r={r} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth={1} />

      {Array.from({ length: 12 }).map((_, pc) => {
        // Place C (pc=0) at 12 o'clock, going clockwise.
        const angle = (pc / 12) * Math.PI * 2 - Math.PI / 2
        const x = cx + Math.cos(angle) * r
        const y = cy + Math.sin(angle) * r

        const semiFromTonic = (pc - t + 12) % 12
        const inKey = mask.has(semiFromTonic)
        const isTonic = pc === t
        const sColor = sounding.get(pc)

        const baseFill = isTonic
          ? "var(--accent)"
          : inKey
            ? "rgba(255,255,255,0.18)"
            : "rgba(255,255,255,0.05)"

        // Dot large enough to fit the label glyph centered on it.
        const dotR = isTonic || sColor ? 16 : 13
        const labelFill =
          isTonic || sColor
            ? "white"
            : inKey
              ? "var(--foreground)"
              : "rgba(255,255,255,0.45)"

        return (
          <g key={pc}>
            {sColor && (
              <circle cx={x} cy={y} r={dotR + 8} fill={sColor} opacity={0.35} />
            )}
            <circle
              cx={x}
              cy={y}
              r={dotR}
              fill={sColor ?? baseFill}
              stroke={isTonic ? "white" : "transparent"}
              strokeWidth={isTonic ? 1.5 : 0}
            />
            <text
              x={x}
              y={y}
              textAnchor="middle"
              dominantBaseline="central"
              fontSize={isTonic || sColor ? 12 : 10}
              fontWeight={isTonic ? 700 : 500}
              fill={labelFill}
              style={{ pointerEvents: "none" }}
            >
              {NOTE_NAMES[pc]}
            </text>
          </g>
        )
      })}

      {/* Center in-scale telltale */}
      <circle
        cx={cx}
        cy={cy}
        r={size * 0.07}
        fill={inScale ? "var(--chart-1)" : "rgba(255,255,255,0.1)"}
        opacity={inScale ? 0.85 : 0.4}
      />
      <text
        x={cx}
        y={cy}
        textAnchor="middle"
        dominantBaseline="central"
        fontSize={9}
        fontWeight={700}
        fill={inScale ? "white" : "rgba(255,255,255,0.5)"}
      >
        {inScale ? "IN" : "OUT"}
      </text>
    </svg>
  )
}
