# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AutoTune is an FPGA-based real-time audio pitch detection and correction system targeting the Intel DE1-SoC board (Cyclone V: 5CSEMA5F31C6). It processes audio via an I2S codec, detects pitch using hardware autocorrelation, and applies PSOLA-based pitch correction. MIDI input provides reference pitch targets.

## Build System

**Primary toolchain**: Intel Quartus Prime 25.1 Lite Edition

- Open project: load `rtl/autotune.qpf` in Quartus
- GUI compilation: Start Compilation from Quartus IDE
- CLI compilation: `quartus_sh --flow compile autotune` (run from `rtl/`)
- Program FPGA: load generated `.sof` file via Quartus Programmer

**Simulation/testbenches**: ModelSim/QuestaSim
```bash
# Run a testbench (from rtl/ or rtl/testbenches/)
vsim -do run.do <testbench_module>
# Example:
vsim -do "vsim autocorrelate_tb; run -all; quit"
```

**Python utilities** (used for generating ROM data and algorithm prototyping):
```bash
cd py && python hanning.py          # Regenerates rtl/hanning.hex (Hanning window ROM)
cd rtl/midi && python generate_lut.py  # Regenerates MIDI note→frequency LUT
```

## Architecture

### Signal Processing Pipeline (Q11.16 fixed-point throughout)

```
I2S ADC → audio_cntrl → clamp_denoise → lpf → hanning window
                                                      ↓
MIDI → midi_receiver → midi_freq_lut          autocorrelate_top
                              ↓                      ↓
                         pitch target         detected pitch period
                              └──────── PSOLA ───────┘
                                            ↓
                                       audio_cntrl → I2S DAC
```

### Key Modules (`rtl/`)

| Module | File | Purpose |
|--------|------|---------|
| `autotune` | `autotune.sv` | Top-level; instantiates all subsystems |
| `audio_cntrl` | `audio_cntrl.sv` | I2S codec control, FIFO, I2C config |
| `fixed` | `fixed.sv` | Q11.16 arithmetic primitives (multiply, convert) |
| `lpf` | `lpf.sv` | Parametric IIR low-pass filter (3-stage cascade: 10kHz left, 400Hz right) |
| `hanning` | `hanning.sv` | ROM lookup for 4096-point Hanning window |
| `clamp_denoise` | `clamp_denoise.sv` | Center-clipping noise gate |
| `autocorrelate_top` | `autocorrelation/autocorrelate_top.sv` | FSM orchestrating multi-lag autocorrelation sweep |
| `autocorrelate` | `autocorrelation/autocorrelate.sv` | Single-lag correlator |
| `circular_buffer` | `autocorrelation/circular_buffer.sv` | FIFO ring buffer for audio samples |
| `memory` | `autocorrelation/memory.sv` | Dual-port RAM |
| `midi` | `midi/midi.sv` | Top-level MIDI processor |
| `midi_receiver` | `midi/midi_receiver.sv` | UART MIDI parser (31.25 kbaud) |
| `midi_freq_lut` | `midi/midi_freq_lut.sv` | MIDI note number → Q11.16 frequency |

### Fixed-Point Format

All DSP arithmetic uses **Q11.16** format (27-bit signed): 11 integer bits + 16 fractional bits. The `fixed.sv` module provides multiply and format-conversion operations.

### Clocks

- `CLOCK_50`: 50 MHz primary (DE1-SoC onboard)
- `AUD_XCK`: 18.432 MHz codec master clock
- `AUD_BCLK`: 1.536 MHz I2S bit clock
- Audio sample rate: 48 kHz, 16-bit stereo

### I/O Pins

- `AUD_ADCDAT/DACDAT`: I2S audio in/out
- `AUD_BCLK`, `AUD_LRCK`: I2S clocks
- `FPGA_I2C_SCLK/SDAT`: Codec config (I2C)
- `IRDA_RXD`: MIDI input (UART)
- `LEDR[9:0]`: Status LEDs (config done, FIFO flags, reset state)

## Python Reference Implementations (`py/`)

These are algorithm prototypes, not synthesized:
- `autocorrelation.py`: Pitch detection via autocorrelation (used to validate RTL)
- `psola2.py`: PSOLA pitch-shifting algorithm reference
- `hanning.py`: Generates `rtl/hanning.hex` — run this when the Hanning window parameters change

## Testbenches (`rtl/testbenches/`)

Each RTL module has a corresponding `_tb.sv` testbench. The autocorrelation module also has testbenches co-located in `rtl/autocorrelation/`.
