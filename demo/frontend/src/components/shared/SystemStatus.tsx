import { useEffect, useState } from "react"
import { AlertTriangleIcon, CheckCircle2Icon, CheckIcon, MinusIcon, XIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { MODE_LABEL } from "@/lib/modeSync"
import type { PitchReading } from "@/types"

interface SystemCheck {
  name: string
  ok: boolean | null
  detail: string
}

function getChecks(connected: boolean, latest: PitchReading | null): SystemCheck[] {
  return [
    {
      name: "WebSocket",
      ok: connected,
      detail: connected ? "Connected" : "Disconnected",
    },
    {
      name: "DAC",
      ok: latest?.dac_full != null ? !latest.dac_full : null,
      detail:
        latest?.dac_full === true
          ? "Buffer full"
          : latest?.dac_full === false
            ? "Ready"
            : "No data",
    },
    // {
    //   name: "ADC",
    //   ok: latest?.adc_empty != null ? !latest.adc_empty : null,
    //   detail:
    //     latest?.adc_empty === true
    //       ? "Buffer empty"
    //       : latest?.adc_empty === false
    //         ? "Ready"
    //         : "No data",
    // },
    {
      name: "Configuration",
      ok:
        latest?.config_done != null && latest?.config_err != null
          ? latest.config_done && !latest.config_err
          : null,
      detail:
        latest?.config_err === true
          ? "Error"
          : latest?.config_done === true
            ? "Done"
            : "No data",
    },
  ]
}

interface Props {
  connected: boolean
  latest: PitchReading | null
}

export function SystemStatus({ connected, latest }: Props) {
  const [open, setOpen] = useState(false)

  const checks = getChecks(connected, latest)
  const failedChecks = checks.filter((c) => c.ok === false)
  const hasError = failedChecks.length > 0
  const allOk = checks.every((c) => c.ok === true)

  useEffect(() => {
    setOpen(hasError)
  }, [hasError])

  const statusText = hasError
    ? "System Error"
    : allOk
      ? "All Systems Operational"
      : "Connecting..."

  const dotClass = hasError
    ? "bg-red-500 shadow-[0_0_6px_theme(colors.red.500)]"
    : allOk
      ? "bg-emerald-500 shadow-[0_0_6px_theme(colors.emerald.500)]"
      : "bg-zinc-600"

  const checkList = (
    <ul className="flex flex-col gap-3">
      {checks.map((check) => (
        <li key={check.name} className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            {check.ok === true ? (
              <CheckIcon className="size-4 shrink-0 text-emerald-500" />
            ) : check.ok === false ? (
              <XIcon className="size-4 shrink-0 text-red-500" />
            ) : (
              <MinusIcon className="size-4 shrink-0 text-zinc-500" />
            )}
            <span className="text-sm font-medium">{check.name}</span>
          </div>
          <span
            className={cn(
              "text-xs",
              check.ok === false ? "text-red-400" : "text-muted-foreground",
            )}
          >
            {check.detail}
          </span>
        </li>
      ))}
    </ul>
  )

  const showModeBadge = latest?.mode === 0 || latest?.mode === 1
  const modeBadgeClass =
    latest?.mode === 0
      ? "bg-red-500/15 text-red-400 ring-red-500/30"
      : "bg-amber-500/15 text-amber-400 ring-amber-500/30"

  return (
    <div className="flex items-center gap-2">
      {showModeBadge && (
        <span
          className={cn(
            "rounded-full px-2 py-0.5 text-xs font-medium uppercase tracking-wide ring-1 ring-inset",
            modeBadgeClass,
          )}
        >
          {MODE_LABEL[latest!.mode!]}
        </span>
      )}
      <button
        onClick={() => setOpen(true)}
        className="flex cursor-pointer items-center gap-2 rounded-full px-2 py-1 transition-colors hover:bg-muted/50"
      >
        <div
          className={cn(
            "size-2 shrink-0 rounded-full transition-colors duration-500",
            dotClass,
          )}
        />
        <span className="text-xs text-muted-foreground">{statusText}</span>
      </button>

      {hasError ? (
        <AlertDialog open={open} onOpenChange={setOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>System Error</AlertDialogTitle>
              <AlertDialogDescription className="sr-only">
                One or more systems are reporting errors.
              </AlertDialogDescription>
            </AlertDialogHeader>

            <Alert variant="destructive">
              <AlertTriangleIcon className="size-4" />
              <AlertTitle>One or more systems are in an error state</AlertTitle>
              <AlertDescription>
                {failedChecks.map((c) => `${c.name}: ${c.detail}`).join(" · ")}
              </AlertDescription>
            </Alert>

            {checkList}

            <AlertDialogFooter>
              <AlertDialogAction onClick={() => setOpen(false)}>
                Dismiss
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      ) : (
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <CheckCircle2Icon className="size-4 text-emerald-500" />
                System Status
              </DialogTitle>
            </DialogHeader>
            {checkList}
          </DialogContent>
        </Dialog>
      )}
    </div>
  )
}
