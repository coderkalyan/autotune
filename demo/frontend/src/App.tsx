import { useCallback, useState } from "react"
import { usePitchSocket } from "@/hooks/usePitchSocket"
import { SplashScreen } from "@/components/splash/SplashScreen"
import { WS_URL } from "@/config"
import type { AppScreen } from "@/types"

// Lazy imports — screens are small but this keeps the initial bundle tight
import { lazy, Suspense } from "react"
const AutotuneScreen = lazy(() =>
  import("@/components/autotune/AutotuneScreen").then((m) => ({ default: m.AutotuneScreen }))
)
const VocoderScreen = lazy(() =>
  import("@/components/vocoder/VocoderScreen").then((m) => ({ default: m.VocoderScreen }))
)

export default function App() {
  const [appScreen, setAppScreen] = useState<AppScreen>({ screen: "splash" })
  const { readings, latest, connected } = usePitchSocket(WS_URL)

  const navigate = useCallback((next: AppScreen) => {
    setAppScreen(next)
  }, [])

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
            />
          </Suspense>
        </div>
      )}

      {appScreen.screen === "vocoder" && (
        <div key="vocoder" className="screen-enter size-full">
          <Suspense fallback={null}>
            <VocoderScreen onNavigate={navigate} />
          </Suspense>
        </div>
      )}
    </div>
  )
}
