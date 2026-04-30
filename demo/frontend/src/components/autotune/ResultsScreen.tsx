import { Star } from "lucide-react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { cn } from "@/lib/utils"
import { formatCents, formatNoteInKey } from "@/lib/noteName"
import type { NoteCompleted } from "@/types"

interface Props {
  open: boolean
  stars: number | null
  score: number | null
  bestCombo: number | null
  songTitle?: string
  songKey?: string | null
  notes: NoteCompleted[]
  onDone: () => void
}

const W_PITCH = 0.85
const W_TIMING = 0.15

function scoreTier(score: number): {
  bar: string
  text: string
} {
  if (score >= 0.85) return { bar: "bg-emerald-500", text: "text-emerald-500" }
  if (score >= 0.55) return { bar: "bg-lime-500", text: "text-lime-500" }
  if (score >= 0.4) return { bar: "bg-amber-500", text: "text-amber-500" }
  return { bar: "bg-rose-500", text: "text-rose-500" }
}

function fmtPct(value: number | null | undefined, digits = 0): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return `${(value * 100).toFixed(digits)}%`
}

function fmtMs(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return "—"
  const sign = value >= 0 ? "+" : "−"
  return `${sign}${Math.round(Math.abs(value))} ms`
}

function fmtNum(
  value: number | null | undefined,
  digits = 2,
  suffix = "",
): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return `${value.toFixed(digits)}${suffix}`
}

export function ResultsScreen({
  open,
  stars,
  score,
  bestCombo,
  songTitle,
  songKey,
  notes,
  onDone,
}: Props) {
  const filled = Math.max(0, Math.min(stars ?? 0, 5))
  const pct = Math.round((score ?? 0) * 100)

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) onDone()
      }}
    >
      <DialogContent
        showCloseButton={false}
        className="flex max-h-[88vh] w-[min(96vw,72rem)] !max-w-[72rem] flex-col gap-4 p-6"
      >
        <DialogHeader className="shrink-0">
          <DialogTitle className="text-xl">Song complete</DialogTitle>
          {songTitle ? (
            <DialogDescription>{songTitle}</DialogDescription>
          ) : null}
        </DialogHeader>

        <div className="flex shrink-0 flex-wrap items-center justify-between gap-4 rounded-lg border bg-muted/30 p-4">
          <div className="flex items-center gap-1">
            {[0, 1, 2, 3, 4].map((i) => (
              <Star
                key={i}
                className={
                  i < filled
                    ? "h-9 w-9 fill-primary stroke-primary"
                    : "h-9 w-9 stroke-muted-foreground/40"
                }
              />
            ))}
          </div>
          <div className="flex items-center gap-6 text-sm">
            <div className="flex flex-col items-end">
              <span className="text-xs uppercase tracking-wide text-muted-foreground">
                Score
              </span>
              <span className="font-mono text-2xl font-semibold tabular-nums">
                {pct}%
              </span>
            </div>
            <div className="flex flex-col items-end">
              <span className="text-xs uppercase tracking-wide text-muted-foreground">
                Best combo
              </span>
              <span className="font-mono text-2xl font-semibold tabular-nums">
                {bestCombo ?? 0}
              </span>
            </div>
            <div className="flex flex-col items-end">
              <span className="text-xs uppercase tracking-wide text-muted-foreground">
                Notes
              </span>
              <span className="font-mono text-2xl font-semibold tabular-nums">
                {notes.length}
              </span>
            </div>
          </div>
        </div>

        <Tabs
          defaultValue="word"
          className="flex min-h-0 flex-1 flex-col gap-3"
        >
          <TabsList className="shrink-0 self-start">
            <TabsTrigger value="word">By word</TabsTrigger>
            <TabsTrigger value="detailed">Detailed</TabsTrigger>
          </TabsList>

          <TabsContent
            value="word"
            className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg border data-[state=inactive]:hidden"
          >
            <ByWordTable notes={notes} songKey={songKey} />
          </TabsContent>

          <TabsContent
            value="detailed"
            className="flex min-h-0 flex-1 flex-col gap-3 data-[state=inactive]:hidden"
          >
            <DetailedView notes={notes} totalScore={score ?? 0} />
          </TabsContent>
        </Tabs>

        <p className="shrink-0 text-center text-xs text-muted-foreground">
          Perfect within ±50¢, partial credit out to ±200¢. "Sang" is the median pitch
          across each lyric's window.
        </p>

        <DialogFooter className="shrink-0">
          <Button onClick={onDone} className="w-full sm:w-auto">
            Done
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

const BY_WORD_GRID =
  "grid-cols-[1.6fr_0.9fr_1.2fr_0.8fr_0.9fr_0.9fr_1.6fr]"

function ByWordTable({
  notes,
  songKey,
}: {
  notes: NoteCompleted[]
  songKey?: string | null
}) {
  return (
    <>
      <div
        className={cn(
          "grid shrink-0 gap-3 border-b bg-muted/40 px-4 py-2 text-xs font-medium uppercase tracking-wide text-muted-foreground",
          BY_WORD_GRID,
        )}
      >
        <span>Lyric</span>
        <span>Expected</span>
        <span>Sang</span>
        <span className="text-right">vs target</span>
        <span className="text-right">Onset</span>
        <span className="text-right">Timing</span>
        <span>Score</span>
      </div>
      {notes.length === 0 ? (
        <div className="flex flex-1 items-center justify-center px-4 py-8 text-sm text-muted-foreground">
          No notes scored.
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto">
          {notes.map((n, i) => {
            const tier = scoreTier(n.score)
            const sangHz = n.detected_pitch_hz ?? null
            const sang = formatNoteInKey(sangHz, songKey, { showCents: true })
            const cents = formatCents(n.cents_off ?? null)
            const pctNote = Math.round(n.score * 100)
            const timingTier =
              n.timing_score != null ? scoreTier(n.timing_score) : null
            return (
              <div
                key={i}
                className={cn(
                  "grid items-center gap-3 border-b px-4 py-2 text-sm last:border-b-0",
                  BY_WORD_GRID,
                )}
              >
                <span className="truncate font-medium">
                  {n.lyric || <span className="text-muted-foreground">—</span>}
                </span>
                <span className="font-mono tabular-nums">
                  {formatNoteInKey(n.pitch_hz, songKey)}
                </span>
                <span
                  className={cn(
                    "font-mono tabular-nums",
                    sangHz === null && "text-muted-foreground",
                  )}
                >
                  {sang}
                </span>
                <span
                  className={cn(
                    "text-right font-mono tabular-nums",
                    n.cents_off == null && "text-muted-foreground",
                  )}
                >
                  {cents}
                </span>
                <span
                  className={cn(
                    "text-right font-mono tabular-nums",
                    n.onset_offset_ms == null && "text-muted-foreground",
                  )}
                >
                  {fmtMs(n.onset_offset_ms)}
                </span>
                <span
                  className={cn(
                    "text-right font-mono tabular-nums",
                    timingTier?.text ?? "text-muted-foreground",
                  )}
                >
                  {fmtPct(n.timing_score)}
                </span>
                <div className="flex items-center gap-2">
                  <div className="relative h-2 flex-1 overflow-hidden rounded-full bg-muted">
                    <div
                      className={cn(
                        "absolute inset-y-0 left-0 rounded-full",
                        tier.bar,
                      )}
                      style={{ width: `${Math.max(2, pctNote)}%` }}
                    />
                  </div>
                  <span
                    className={cn(
                      "w-10 shrink-0 text-right font-mono text-xs font-medium tabular-nums",
                      tier.text,
                    )}
                  >
                    {pctNote}%
                  </span>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </>
  )
}

const DETAIL_GRID =
  "grid-cols-[1.6fr_0.9fr_0.9fr_0.7fr_0.8fr_0.8fr_0.9fr_0.7fr_0.7fr_0.8fr_0.9fr]"

function DetailedView({
  notes,
  totalScore,
}: {
  notes: NoteCompleted[]
  totalScore: number
}) {
  // Walk notes in order, tracking the running weighted average so each row
  // shows what the cumulative score was at the moment that note ended.
  let runningWeighted = 0
  let runningWeight = 0
  const rows = notes.map((n) => {
    const w = n.weight ?? 0
    runningWeighted += n.score * w
    runningWeight += w
    const cumulative = runningWeight > 0 ? runningWeighted / runningWeight : 0
    return { n, cumulative }
  })

  return (
    <>
      <div className="shrink-0 rounded-lg border bg-muted/30 p-3 font-mono text-xs leading-relaxed text-muted-foreground">
        <div>
          score = {W_PITCH} · pitch + {W_TIMING} · timing
        </div>
        <div>pitch = 1.0 within ±50¢, linear falloff to 0 at ±200¢</div>
        <div>timing = 1.0 within ±100 ms, linear falloff to 0 at ±300 ms</div>
        <div>weight = √(duration_s); final = Σ(score · weight) / Σweight</div>
      </div>

      <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg border">
        <div
          className={cn(
            "grid shrink-0 gap-2 border-b bg-muted/40 px-3 py-2 text-[10px] font-medium uppercase tracking-wide text-muted-foreground",
            DETAIL_GRID,
          )}
        >
          <span>Lyric</span>
          <span className="text-right">Target Hz</span>
          <span className="text-right">Sang Hz</span>
          <span className="text-right">¢off</span>
          <span className="text-right">Pitch</span>
          <span className="text-right">Timing</span>
          <span className="text-right">Onset</span>
          <span className="text-right">Dur</span>
          <span className="text-right">Weight</span>
          <span className="text-right">Note</span>
          <span className="text-right">Cumul.</span>
        </div>
        {rows.length === 0 ? (
          <div className="flex flex-1 items-center justify-center px-4 py-8 text-sm text-muted-foreground">
            No notes scored.
          </div>
        ) : (
          <div className="min-h-0 flex-1 overflow-y-auto">
            {rows.map(({ n, cumulative }, i) => {
              const tier = scoreTier(n.score)
              const cumTier = scoreTier(cumulative)
              return (
                <div
                  key={i}
                  className={cn(
                    "grid items-center gap-2 border-b px-3 py-1.5 text-xs last:border-b-0",
                    DETAIL_GRID,
                  )}
                >
                  <span className="truncate font-medium">
                    {n.lyric || (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </span>
                  <span className="text-right font-mono tabular-nums">
                    {fmtNum(n.pitch_hz, 2)}
                  </span>
                  <span
                    className={cn(
                      "text-right font-mono tabular-nums",
                      n.detected_pitch_hz == null && "text-muted-foreground",
                    )}
                  >
                    {fmtNum(n.detected_pitch_hz, 2)}
                  </span>
                  <span
                    className={cn(
                      "text-right font-mono tabular-nums",
                      n.cents_off == null && "text-muted-foreground",
                    )}
                  >
                    {formatCents(n.cents_off ?? null)}
                  </span>
                  <span className="text-right font-mono tabular-nums">
                    {fmtPct(n.pitch_score)}
                  </span>
                  <span className="text-right font-mono tabular-nums">
                    {fmtPct(n.timing_score)}
                  </span>
                  <span
                    className={cn(
                      "text-right font-mono tabular-nums",
                      n.onset_offset_ms == null && "text-muted-foreground",
                    )}
                  >
                    {fmtMs(n.onset_offset_ms)}
                  </span>
                  <span className="text-right font-mono tabular-nums">
                    {fmtNum(n.duration_ms, 0, " ms")}
                  </span>
                  <span className="text-right font-mono tabular-nums">
                    {fmtNum(n.weight, 2)}
                  </span>
                  <span
                    className={cn(
                      "text-right font-mono font-medium tabular-nums",
                      tier.text,
                    )}
                  >
                    {fmtPct(n.score)}
                  </span>
                  <span
                    className={cn(
                      "text-right font-mono tabular-nums",
                      cumTier.text,
                    )}
                  >
                    {fmtPct(cumulative)}
                  </span>
                </div>
              )
            })}
          </div>
        )}
        <div
          className={cn(
            "grid shrink-0 gap-2 border-t bg-muted/40 px-3 py-2 text-xs font-medium",
            DETAIL_GRID,
          )}
        >
          <span className="text-muted-foreground">Totals</span>
          <span />
          <span />
          <span />
          <span />
          <span />
          <span />
          <span />
          <span className="text-right font-mono tabular-nums">
            Σ {fmtNum(runningWeight, 2)}
          </span>
          <span className="text-right font-mono tabular-nums">
            Σw·s {fmtNum(runningWeighted, 2)}
          </span>
          <span
            className={cn(
              "text-right font-mono tabular-nums",
              scoreTier(totalScore).text,
            )}
          >
            {fmtPct(totalScore)}
          </span>
        </div>
      </div>
    </>
  )
}
