import { FrequencyChart } from "@/components/FrequencyChart"
import { SerialStatus } from "@/components/SerialStatus"
import { useFrequencyData } from "@/hooks/useWebSocket"

export default function App() {
  const { points, connected } = useFrequencyData()

  return (
    <div className="h-screen flex flex-col p-4 gap-4 bg-background">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Autotune — Live Pitch</h1>
        <SerialStatus connected={connected} />
      </div>
      <div className="flex-1 min-h-0">
        <FrequencyChart points={points} />
      </div>
    </div>
  )
}
