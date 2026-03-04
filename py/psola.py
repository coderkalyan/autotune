import subprocess
import matplotlib.pyplot as plt
import numpy as np


def _stem(ax, n, y, title: str, xlabel: str, ylabel: str) -> None:
    """Small helper to make discrete-time style plots."""
    markerline, stemlines, baseline = ax.stem(n, y)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.3)
    # Make it a bit cleaner looking
    try:
        markerline.set_markersize(4)
        stemlines.set_linewidth(1)
        baseline.set_linewidth(1)
    except Exception:
        pass

def discrete_time_sinusoid(
    N: int,
    amplitude: float = 1.0,
    f0_hz: float = 5.0,
    fs_hz: float = 100.0,
    phase_rad: float = 0.0,
    kind: str = "sin",
) -> np.ndarray:
    """Generate a discrete-time sinusoid x[n] of length N.

    x[n] = A * sin(2*pi*f0*n/fs + phi)   (or cos if kind='cos')
    """
    n = np.arange(N, dtype=float)

    omega_n = 2.0 * np.pi * (f0_hz / fs_hz) * n + phase_rad
    # print(omega_n[:10])

    kind = kind.lower().strip()
    if kind == "sin":
        return amplitude * np.sin(omega_n)
    if kind == "cos":
        return amplitude * np.cos(omega_n)
    raise ValueError("kind must be 'sin' or 'cos'")

def mp4_audio_to_signal(
    *,
    mp4_path: str,
    target_fs_hz: int = 16_000,
    start_time_sec: float = 0.0,
    duration_sec: float = 5.0,
    max_samples: int = 65_536,
    normalize: bool = True,
) -> tuple[np.ndarray, int]:
    """Extract MP4 audio using ffmpeg and return a discrete-time signal.

    This shells out to `ffmpeg` (must be installed) and decodes audio to
    mono float32 samples.

    Notes
    -----
    - By default this only extracts the first 5 seconds (customize with
      `start_time_sec` and `duration_sec`).
    - The returned `x` is truncated to at most `max_samples` as a safety cap.
    - `target_fs_hz` sets the resample rate used by ffmpeg.
    """
    if target_fs_hz <= 0:
        raise ValueError("target_fs_hz must be positive")
    if max_samples <= 0:
        raise ValueError("max_samples must be positive")
    if start_time_sec < 0:
        raise ValueError("start_time_sec must be non-negative")
    if duration_sec <= 0:
        raise ValueError("duration_sec must be positive")

    cmd = [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        str(start_time_sec),
        "-t",
        str(duration_sec),
        "-i",
        mp4_path,
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(int(target_fs_hz)),
        "-acodec",
        "pcm_f32le",
        "-f",
        "f32le",
        "pipe:1",
    ]

    proc = subprocess.run(cmd, check=False, capture_output=True)
    if proc.returncode != 0:
        stderr = (proc.stderr or b"").decode(errors="replace").strip()
        raise RuntimeError(
            "ffmpeg failed to decode audio from MP4. "
            "Check mp4_path and that the file contains audio. "
            f"ffmpeg stderr: {stderr}"
        )

    x = np.frombuffer(proc.stdout, dtype=np.float32)
    if x.size == 0:
        raise RuntimeError("No audio samples decoded (empty output).")

    # Safety cap in case the container yields more samples than expected.
    x = x[:max_samples].astype(np.float64, copy=False)
    x = x - float(np.mean(x))
    if normalize:
        peak = float(np.max(np.abs(x)))
        if peak > 0:
            x = x / peak

    return x, int(target_fs_hz)

import numpy as np

def centered_hamming_window(
    x: np.ndarray,
    center_idx: int,
    taper_len: int
) -> np.ndarray:
    """
    Apply a Hamming window centered at a specific sample.

    Parameters
    ----------
    x : np.ndarray
        Input signal.
    center_idx : int
        Sample index where the window is centered.
    taper_len : int
        Half-width of the window (distance from center).

    Returns
    -------
    np.ndarray
        Windowed signal.
    """

    center_idx = int(round(center_idx))  
    taper_len = int(taper_len) 

    x = np.asarray(x)
    N = len(x)

    w = np.zeros(N)

    start = max(0, center_idx - taper_len)
    end = min(N, center_idx + taper_len) 

    length = end - start
    if length <= 0:
        return x

    h = np.hamming(length)

    w[start:end] = h

    return x * w


def main_mp4_audio() -> None:
    """Alternate entry-point: MP4 -> audio samples -> autocorrelation plots.

    Edit the `mp4_path` string to point to your local MP4.
    """
    mp4_path = r"10 Minutes of A Piano A4 440 Hz - Music in Space.mp3"  # TODO: hard-code your file path here

    x, fs_hz = mp4_audio_to_signal(
        mp4_path=mp4_path, 
        target_fs_hz=16_000, 
        start_time_sec=0.5,
        duration_sec=4.0,
        max_samples=65_536
    )


    max_lag = min(128, x.shape[0])
    lag_sec = np.arange(max_lag) / fs_hz
    t_sec = np.arange(x.shape[0]) / fs_hz



    # fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), constrained_layout=True)
    fig, (ax1) = plt.subplots(1, 1, figsize=(10, 6), constrained_layout=True)
    ax1.plot(t_sec, x, linewidth=0.8)
    ax1.set_title("MP4 Audio (time domain)")
    ax1.set_xlabel("time (s)")
    ax1.set_ylabel("x[n] (normalized)")
    ax1.grid(True, alpha=0.3)

    # ax2.stem(t_sec, x_win)
    # ax2.set_title("Hamming window on Audio File")
    # ax2.set_xlabel("lag (s)")
    # ax2.set_ylabel("x[n] normalized")
    # ax2.grid(True, alpha=0.3)

    plt.show()


def simple_psola_demo() -> None:
    # --- Example usage ---
    N = 64 * 12
    amplitude = 1
    f0= 4.0
    fs = 128*4
    center_mark = 128
    samples_per_period = fs / f0
    rng = np.random.default_rng(0)

    x = discrete_time_sinusoid(
        N, amplitude=amplitude, f0_hz=f0, fs_hz=fs, phase_rad=np.pi, kind="sin"
    )

    hamming_marks = list()
    m_k = list()
    for i in range(N): 
        temp1 = center_mark + (i*samples_per_period)
        if temp1 <= N-128:
            temp2 = centered_hamming_window(x,temp1,128)
            hamming_marks.append(temp2)

    #x_win = centered_hamming_window(x,center_mark,128)

    pitch_factor = 0.5
    target_pitch = pitch_factor * f0
    sample_shift = samples_per_period / pitch_factor




    n = np.arange(N)
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8, 6), constrained_layout=True)
    #fig, (ax1) = plt.subplots(1, 1, figsize=(8, 6), constrained_layout=True)
    _stem(
        ax1,
        n,
        x,
        title="Discrete-time sinusoid x[n]",
        xlabel="n (sample)",
        ylabel="x[n]",
    )
    _stem(ax2, n, x_win, title="Centered Hamming Window x[n]", xlabel="n (samples)", ylabel="x[n]")
    plt.show()

if __name__ == "__main__":
    #main_mp4_audio()
    simple_psola_demo()