import { useCallback, useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import { usePitchSocket } from "@/hooks/usePitchSocket"
import { useSongPlayback } from "@/hooks/useSongPlayback"
import { SplashScreen } from "@/components/splash/SplashScreen"
import { Toaster } from "@/components/ui/sonner"
import { SCREEN_TO_MODE, screenForMode } from "@/lib/modeSync"
import { WS_URL } from "@/config"
import type { AppScreen, UARTMode } from "@/types"

// Lazy imports — screens are small but this keeps the initial bundle tight
import { lazy, Suspense } from "react"
const AutotuneScreen = lazy(() =>
  import("@/components/autotune/AutotuneScreen").then((m) => ({ default: m.AutotuneScreen }))
)
const VocoderScreen = lazy(() =>
  import("@/components/vocoder/VocoderScreen").then((m) => ({ default: m.VocoderScreen }))
)
const SynthScreen = lazy(() =>
  import("@/components/synth/SynthScreen").then((m) => ({ default: m.SynthScreen }))
)
const HarmonyScreen = lazy(() =>
  import("@/components/harmony/HarmonyScreen").then((m) => ({ default: m.HarmonyScreen }))
)

export default function App() {
  const [appScreen, setAppScreen] = useState<AppScreen>({ screen: "splash" })
  const playback = useSongPlayback()
  const { readings, latest, connected, sendMessage } = usePitchSocket(WS_URL, playback.getPlayback)
  const lastSeenModeRef = useRef<UARTMode | null>(null)

  const navigate = useCallback(
    (next: AppScreen) => {
      const mode = SCREEN_TO_MODE[next.screen]
      if (mode !== undefined) {
        sendMessage({ type: "mode_change", mode })
      }
      setAppScreen(next)
    },
    [sendMessage],
  )

  useEffect(() => {
    const mode = latest?.mode ?? null
    if (mode === lastSeenModeRef.current) return
    const prev = lastSeenModeRef.current
    lastSeenModeRef.current = mode
    if (prev === null) return // first frame — keep splash sticky on cold load

    // Sing-along is locked to AUTOTUNE. Revert any external mode change.
    if (
      appScreen.screen === "autotune" &&
      appScreen.selectedSong !== null &&
      mode !== 2
    ) {
      toast.info("Mode locked during sing-along")
      sendMessage({ type: "mode_change", mode: 2 })
      return
    }

    const next = screenForMode(mode)
    if (next === null) return // MUTE / PASSTHROUGH / HARMONY — no nav
    if (next.screen !== appScreen.screen) {
      setAppScreen(next)
    }
  }, [latest?.mode, appScreen, sendMessage])

  return (
    <div className="size-full overflow-hidden bg-background">
      {appScreen.screen === "splash" && (
        <div key="splash" className="screen-enter size-full">
          <SplashScreen onNavigate={navigate} />
        </div>
      )}

      {appScreen.screen === "autotune" && (
        <div key="autotune" className="screen-enter size-full">
          <Suspense fallback={null}>
            <AutotuneScreen
              screenState={appScreen}
              onNavigate={navigate}
              readings={readings}
              latest={latest}
              connected={connected}
              playback={playback}
            />
          </Suspense>
        </div>
      )}

      {appScreen.screen === "vocoder" && (
        <div key="vocoder" className="screen-enter size-full">
          <Suspense fallback={null}>
            <VocoderScreen onNavigate={navigate} latest={latest} connected={connected} />
          </Suspense>
        </div>
      )}

      {appScreen.screen === "synth" && (
        <div key="synth" className="screen-enter size-full">
          <Suspense fallback={null}>
            <SynthScreen
              onNavigate={navigate}
              latest={latest}
              connected={connected}
              sendMessage={sendMessage}
            />
          </Suspense>
        </div>
      )}

      {appScreen.screen === "harmony" && (
        <div key="harmony" className="screen-enter size-full">
          <Suspense fallback={null}>
            <HarmonyScreen
              onNavigate={navigate}
              latest={latest}
              connected={connected}
            />
          </Suspense>
        </div>
      )}

      <Toaster />
    </div>
  )
}
