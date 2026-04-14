import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import type { AutotuneSubMode } from "@/types"

interface Props {
  value: AutotuneSubMode
  onValueChange: (value: AutotuneSubMode) => void
}

export function SubModeToggle({ value, onValueChange }: Props) {
  return (
    <Tabs value={value} onValueChange={(v) => onValueChange(v as AutotuneSubMode)}>
      <TabsList className="w-64">
        <TabsTrigger value="free" className="flex-1">
          Free Play
        </TabsTrigger>
        <TabsTrigger value="sing-along" className="flex-1">
          Sing Along
        </TabsTrigger>
      </TabsList>
    </Tabs>
  )
}
