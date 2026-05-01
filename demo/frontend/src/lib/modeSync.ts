import type { AppScreen, UARTMode } from "@/types"

export const MODE_LABEL: Record<number, string> = {
  0: "Mute",
  1: "Passthrough",
  2: "Autotune",
  3: "Vocoder",
  4: "Synth",
  5: "Harmony",
}

export const MODE_TO_SCREEN: Record<number, AppScreen["screen"] | null> = {
  0: null,
  1: null,
  2: "autotune",
  3: "vocoder",
  4: "synth",
  5: "harmony",
}

export const SCREEN_TO_MODE: Partial<Record<AppScreen["screen"], UARTMode>> = {
  autotune: 2,
  vocoder: 3,
  synth: 4,
  harmony: 5,
}

export function screenForMode(mode: UARTMode | null | undefined): AppScreen | null {
  if (mode == null) return null
  const screen = MODE_TO_SCREEN[mode]
  if (screen === "autotune") return { screen: "autotune", subMode: "free", selectedSong: null }
  if (screen === "vocoder") return { screen: "vocoder" }
  if (screen === "synth") return { screen: "synth" }
  if (screen === "harmony") return { screen: "harmony" }
  return null
}
