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

interface Props {
  open: boolean
  stars: number | null      // 0..5
  score: number | null      // 0..1
  bestCombo: number | null
  songTitle?: string
  onDone: () => void
}

export function ResultsScreen({
  open,
  stars,
  score,
  bestCombo,
  songTitle,
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
      <DialogContent showCloseButton={false}>
        <DialogHeader>
          <DialogTitle>Song complete</DialogTitle>
          {songTitle ? (
            <DialogDescription>{songTitle}</DialogDescription>
          ) : null}
        </DialogHeader>

        <div className="flex flex-col items-center gap-4 py-4">
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

          <div className="grid grid-cols-2 gap-x-8 gap-y-1 text-sm">
            <span className="text-muted-foreground">Score</span>
            <span className="font-mono font-medium tabular-nums text-right">
              {pct}%
            </span>
            <span className="text-muted-foreground">Best combo</span>
            <span className="font-mono font-medium tabular-nums text-right">
              {bestCombo ?? 0}
            </span>
          </div>
        </div>

        <DialogFooter>
          <Button onClick={onDone} className="w-full">
            Done
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
