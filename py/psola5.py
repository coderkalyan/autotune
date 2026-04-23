import sys
import numpy as np
import wave
import argparse
from tqdm import tqdm

# ==============================================================================
# Hardware Constants & Configuration
# ==============================================================================

RING_SIZE = 2048
NUM_CHANNELS = 32
FADE_LENGTH = 32
SAMPLE_RATE = 48000

# Pitch detection configuration
PITCH_MIN_LAG = 48   # ~1000Hz
PITCH_MAX_LAG = 600  # ~80Hz
PITCH_DETECT_PERIOD = 256

# ==============================================================================
# Hardware State (Module-Level Registers)
# ==============================================================================

# Ring Buffer: 2048 x float32
# Treated as a hardware register file
ring_buffer = np.zeros(RING_SIZE, dtype=np.float32)
write_ptr = 0

# Epoch Generator State
epoch_accum = 0.0     # Float phase accumulator
current_T = 100       # Initial pitch period
last_epoch_int = 0
shift_ratio = 1.0

# Diagnostics
eviction_count = 0

# Virtual Channels State (Struct of Arrays for Numpy Speedup)
# In hardware, this would be 32 instances of a struct.
# Here, we use arrays to allow vectorized operations.
ch_active = np.zeros(NUM_CHANNELS, dtype=bool)
ch_grain_center = np.zeros(NUM_CHANNELS, dtype=np.int32)
ch_grain_T = np.zeros(NUM_CHANNELS, dtype=np.int32)
ch_playback_pos = np.zeros(NUM_CHANNELS, dtype=np.int32)
ch_fading_out = np.zeros(NUM_CHANNELS, dtype=bool)
ch_fade_remaining = np.zeros(NUM_CHANNELS, dtype=np.float32) # Float for simpler math

# ==============================================================================
# Pitch Detector
# ==============================================================================

def detect_pitch(samples, sample_rate=48000):
    """
    Normalized autocorrelation pitch detector using Numpy.
    """
    n_samples = len(samples)
    if n_samples < PITCH_MAX_LAG + PITCH_MIN_LAG:
        return PITCH_MIN_LAG
        
    W = n_samples - PITCH_MAX_LAG
    if W < PITCH_MIN_LAG: W = n_samples // 2

    signal = np.array(samples, dtype=np.float32)
    
    # 1. Base window x[0:W]
    base_window = signal[:W]
    base_energy = np.sum(base_window**2)
    
    if base_energy == 0: return PITCH_MIN_LAG
    
    # 2. Compute energies for all sliding windows using cumsum
    signal_sq = signal**2
    cumsum_sq = np.concatenate(([0], np.cumsum(signal_sq)))
    
    # We want energies of windows starting at lag L, length W
    # Energy[L] = cumsum[L+W] - cumsum[L]
    lags = np.arange(PITCH_MIN_LAG, PITCH_MAX_LAG + 1)
    
    # Ensure we don't go out of bounds
    valid_lags_mask = (lags + W) <= n_samples
    lags = lags[valid_lags_mask]
    if len(lags) == 0: return PITCH_MIN_LAG

    lag_energies = cumsum_sq[lags + W] - cumsum_sq[lags]
    lag_energies[lag_energies == 0] = 1e-9 # Prevent div by zero
    
    # 3. Compute cross-correlation
    # We want dot(signal[lag:lag+W], base_window) for each lag.
    # We can use np.correlate. 
    # correlate(a, v, mode='valid') does dot products of sliding window of 'a' with 'v'.
    # If 'v' is length W, and 'a' is longer.
    # To get lag 0 (overlap start-start), we need `a` to start at 0.
    # To get lag MIN_LAG, we need `a` to start at MIN_LAG.
    
    # We extract the relevant search region from signal
    # We need lags from MIN to MAX.
    # The last window starts at MAX_LAG and ends at MAX_LAG+W.
    end_idx = lags[-1] + W
    search_region = signal[PITCH_MIN_LAG : end_idx]
    
    if len(search_region) < len(base_window):
        return PITCH_MIN_LAG
        
    # Valid correlation
    # This computes dot products for offsets 0, 1, 2... within search_region
    # Offset 0 in search_region corresponds to lag PITCH_MIN_LAG in original signal
    cross_corr = np.correlate(search_region, base_window, mode='valid')
    
    # Truncate to match lags length (in case bounds differ slightly)
    min_len = min(len(cross_corr), len(lags))
    cross_corr = cross_corr[:min_len]
    lag_energies = lag_energies[:min_len]
    lags = lags[:min_len]
    
    # Normalized correlation
    norm_corr = cross_corr / np.sqrt(base_energy * lag_energies)
    
    best_idx = np.argmax(norm_corr)
    return lags[best_idx]


# ==============================================================================
# Channel Management
# ==============================================================================

def allocate_channel(grain_center, grain_T):
    """
    Allocate a channel for a new grain.
    """
    global eviction_count
    
    # 1. Find first idle channel
    idle_indices = np.where(~ch_active)[0]
    
    if len(idle_indices) > 0:
        idx = idle_indices[0]
        ch_active[idx] = True
        ch_grain_center[idx] = grain_center
        ch_grain_T[idx] = grain_T
        ch_playback_pos[idx] = 0
        ch_fading_out[idx] = False
        ch_fade_remaining[idx] = 0
        return

    # 2. Evict channel with highest progress
    denoms = 2 * ch_grain_T
    # Calculate progress for active channels only to avoid div by zero or noise
    # But for simplicity we can just compute all and mask
    denoms[denoms == 0] = 1 # Avoid div by zero
    progress = ch_playback_pos / denoms
    
    # Only consider active channels for eviction
    # Set progress of inactive to -1
    progress[~ch_active] = -1.0
    
    best_idx = np.argmax(progress)
    
    if ch_active[best_idx]:
        # Eviction logic: restart channel with fade-in
        ch_fading_out[best_idx] = True
        ch_fade_remaining[best_idx] = FADE_LENGTH
        ch_active[best_idx] = True
        ch_grain_center[best_idx] = grain_center
        ch_grain_T[best_idx] = grain_T
        ch_playback_pos[best_idx] = 0
        
        eviction_count += 1
    else:
        # Should not happen if we check idle first, unless all inactive?
        # If all inactive, idle check would have found one.
        # So this branch implies all active.
        pass

# ==============================================================================
# Main Processing Loop
# ==============================================================================

def process_sample(sample_in):
    global write_ptr, epoch_accum, current_T, last_epoch_int, eviction_count
    
    # Stage 1 — Write input to ring buffer
    ring_buffer[write_ptr % RING_SIZE] = float(sample_in)
    write_ptr += 1

    # Stage 2 — Pitch detector (every 256 ticks)
    if write_ptr % PITCH_DETECT_PERIOD == 0:
        chunk_len = 1024
        # Handle wrapping for chunk extraction
        start_idx = (write_ptr - chunk_len) % RING_SIZE
        if start_idx + chunk_len <= RING_SIZE:
            chunk = ring_buffer[start_idx : start_idx + chunk_len]
        else:
            p1 = ring_buffer[start_idx:]
            p2 = ring_buffer[:chunk_len - len(p1)]
            chunk = np.concatenate((p1, p2))
            
        current_T = detect_pitch(chunk, SAMPLE_RATE)

    # Stage 3 — Epoch generator
    # Target period = T / Ratio
    grain_period = current_T / shift_ratio
    if grain_period < 1.0: grain_period = 1.0
    
    # Phase increment = 1.0 / Period
    phase_inc = 1.0 / grain_period
    epoch_accum += phase_inc
    
    current_epoch_val = int(epoch_accum)
    if current_epoch_val > last_epoch_int:
        last_epoch_int = current_epoch_val
        # Fire grain event
        center = (write_ptr - current_T) % RING_SIZE
        allocate_channel(center, current_T)

    # Stage 4 — Channel Processing (Vectorized)
    # Check if any active
    if not np.any(ch_active):
        return 0.0

    # Get active indices
    active_mask = ch_active
    
    # Get state for active channels
    centers = ch_grain_center[active_mask]
    Ts = ch_grain_T[active_mask]
    pos = ch_playback_pos[active_mask]
    
    # Compute Read Index
    # (grain_center - grain_T + playback_pos) % RING_SIZE
    read_indices = (centers - Ts + pos) % RING_SIZE
    
    # Read samples (Vectorized random access)
    samples = ring_buffer[read_indices]
    
    # Hanning window
    grain_lens = 2 * Ts - 1
    grain_lens[grain_lens < 1] = 1 # Avoid div by zero
    
    # w = 0.5 * (1 - cos(2*pi*pos / (2*T - 1)))
    # Using float math (np.cos)
    coeffs = 0.5 * (1.0 - np.cos(2.0 * np.pi * pos / grain_lens))
    
    contributions = samples * coeffs
    
    # Apply fade
    fading_mask = ch_fading_out[active_mask]
    if np.any(fading_mask):
        remaining = ch_fade_remaining[active_mask]
        # Scalar = remaining/LEN for fading channels, 1.0 otherwise
        scalars = np.ones(len(contributions), dtype=np.float32)
        # Apply fade scale only where fading
        scalars[fading_mask] = remaining[fading_mask] / FADE_LENGTH
        contributions *= scalars
        
    accumulator = np.sum(contributions)
    
    # Stage 6 — Advance state
    # Update position for active channels
    ch_playback_pos[active_mask] += 1
    
    # Update fade remaining
    # Use boolean indexing on the global arrays to update state in place
    
    # Indices that are active AND fading
    fading_active_mask = ch_active & ch_fading_out
    
    if np.any(fading_active_mask):
        ch_fade_remaining[fading_active_mask] -= 1
        
        # Stop fading if done (<=0)
        # We need to check only those we just decremented
        done_fading_mask = fading_active_mask & (ch_fade_remaining <= 0)
        ch_fading_out[done_fading_mask] = False
        
    # Deactivate if playback finished
    finished_mask = ch_active & (ch_playback_pos >= 2 * ch_grain_T)
    ch_active[finished_mask] = False

    return accumulator

# ==============================================================================
# Main Execution
# ==============================================================================

def main():
    global shift_ratio
    
    if len(sys.argv) < 3:
        print("Usage: python psola.py <input.pcm> <shift_ratio> <output.wav>", file=sys.stderr)
        sys.exit(1)
        
    input_path = sys.argv[1]
    shift_ratio = float(sys.argv[2])
    output_wav_path = sys.argv[3]
    
    print(f"Shift Ratio: {shift_ratio}", file=sys.stderr)
    
    # Read input file
    # Assuming raw 16-bit signed PCM little-endian
    try:
        with open(input_path, 'rb') as f:
            raw_data = f.read()
    except FileNotFoundError:
        print(f"Error: Input file '{input_path}' not found.", file=sys.stderr)
        sys.exit(1)
        
    # Load as int16
    samples = np.frombuffer(raw_data, dtype=np.int16)
    num_samples = len(samples)
    
    print(f"Processing {num_samples} samples...", file=sys.stderr)
    
    # Pre-allocate output
    out_arr = np.zeros(num_samples, dtype=np.int16)
    
    # Use a loop over samples
    # Optimized loop would be block based, but adhering to 'process_sample' structure
    # To reduce python function call overhead, we could inline, but sticking to structure
    
    for i in tqdm(range(num_samples)):
        val = process_sample(samples[i])
        
        # Clip
        if val > 32767: val = 32767
        elif val < -32768: val = -32768
        out_arr[i] = int(val)
        
        if i % 10000 == 0 and i > 0:
             # Just a lightweight progress/diagnostic print
             pass

    # Write Output WAV
    with wave.open(output_wav_path, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(out_arr.tobytes())
        
    print("Done.", file=sys.stderr)

if __name__ == "__main__":
    main()
