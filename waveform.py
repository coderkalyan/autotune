import subprocess

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


def add_noise(
    x: np.ndarray,
    *,
    mean: float = 0.0,
    std: float = 0.1,
    rng: np.random.Generator | None = None,
) -> np.ndarray:
    """Return x with additive white Gaussian noise.

    Parameters
    ----------
    x:
        Input signal.
    mean, std:
        Noise mean and standard deviation.
    rng:
        Optional NumPy RNG for reproducibility.
    """
    x = np.asarray(x)
    if rng is None:
        rng = np.random.default_rng()
    noise = rng.normal(mean, std, size=x.shape)
    return x + noise


def add_harmonics(
    x: np.ndarray,
    *,
    f0_hz: float,
    fs_hz: float,
    num_harmonics: int = 3,
    relative_amplitude: float = 0.2,
    amplitude_decay: float = 1.0,
    rng: np.random.Generator | None = None,
    kind: str = "sin",
) -> np.ndarray:
    """Add smaller-amplitude harmonics (2*f0, 3*f0, ...) with random phase.

    The k-th harmonic (k=2..num_harmonics+1) is added as:
        A_k * sin(2*pi*(k*f0)*n/fs + phi_k)

    where A_k = A_base * relative_amplitude / (k ** amplitude_decay)
    and phi_k is uniform on [0, 2*pi).
    """
    x = np.asarray(x, dtype=float)
    N = x.shape[0]
    n = np.arange(N, dtype=float)

    if rng is None:
        rng = np.random.default_rng()

    # Use the current signal's peak amplitude as a reasonable scale.
    base_peak = float(np.max(np.abs(x))) if N else 0.0

    kind = kind.lower().strip()
    if kind not in {"sin", "cos"}:
        raise ValueError("kind must be 'sin' or 'cos'")

    y = x.copy()
    for k in range(2, 2 + int(num_harmonics)):
        phase = float(rng.uniform(0.0, 2.0 * np.pi))
        Ak = base_peak * float(relative_amplitude) / (k ** float(amplitude_decay))
        omega_n = 2.0 * np.pi * ((k * f0_hz) / fs_hz) * n + phase
        if kind == "sin":
            y += Ak * np.sin(omega_n)
        else:
            y += Ak * np.cos(omega_n)
    return y


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


def main_mp4_audio_autocorr() -> None:
    """Alternate entry-point: MP4 -> audio samples -> autocorrelation plots.

    Edit the `mp4_path` string to point to your local MP4.
    """
    mp4_path = r"/home/laptop4070/ece554/10 Minutes of A Piano A4 440 Hz - Music in Space.mp3"  # TODO: hard-code your file path here

    # Keep this modest: r_of_n is O(N * max_lag) in your current implementation.
    x, fs_hz = mp4_audio_to_signal(mp4_path=mp4_path, target_fs_hz=16_000, max_samples=65_536)
    r = r_of_n(x)

    max_lag = min(128, x.shape[0])
    lag_sec = np.arange(max_lag) / fs_hz
    t_sec = np.arange(x.shape[0]) / fs_hz

    import matplotlib.pyplot as plt

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), constrained_layout=True)
    ax1.plot(t_sec, x, linewidth=0.8)
    ax1.set_title("MP4 Audio (time domain)")
    ax1.set_xlabel("time (s)")
    ax1.set_ylabel("x[n] (normalized)")
    ax1.grid(True, alpha=0.3)

    ax2.stem(lag_sec, r[:max_lag])
    ax2.set_title("Autocorrelation r[n] (first lags)")
    ax2.set_xlabel("lag (s)")
    ax2.set_ylabel("r[n]")
    ax2.grid(True, alpha=0.3)

    plt.show()


def r_of_n(x: np.ndarray) -> np.ndarray:
    """Compute r(n) = sum_{k=0}^{N-n-1} x[k] * x[k+n] for n=0..N-1."""
    x = np.asarray(x)
    N = x.shape[0]
    r = np.zeros(N, dtype=np.result_type(x, np.float64))
    for n in range(128):
    # for n in range(N):
        # sum_{k=0}^{N-n-1} x[k]*x[k+n]
        r[n] = np.dot(x[: N - n], x[n:]) / N
    return r

def simple_auto_correlation_demo() -> None:
    # --- Example usage ---
    N = 64 * 4
    amplitude = 1
    rng = np.random.default_rng(0)

    x = discrete_time_sinusoid(
        N, amplitude=amplitude, f0_hz=5.0, fs_hz=128.0*4, phase_rad=np.pi, kind="sin"
    )

    # Add harmonics to the clean signal, then add noise.
    x = add_harmonics(
        x,
        f0_hz=5.0,
        fs_hz=128.0,
        num_harmonics=3,
        relative_amplitude=0.5,
        amplitude_decay=1,
        rng=rng,
        kind="sin",
    )
    x = add_noise(x, mean=0.0, std=10 / 100, rng=rng)

    r = r_of_n(x)

    # x is the waveform, r[n] is the summation result for each lag n
    print("x (first 10 samples):", np.round(x[:10], 6))
    print("r (first 10 lags):   ", np.round(r[:10], 6))

    # --- Plot x[n] and r[n] ---
    # If you don't have matplotlib installed: pip install matplotlib
    import matplotlib.pyplot as plt

    n = np.arange(N)
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8, 6), constrained_layout=True)
    _stem(
        ax1,
        n,
        x,
        title="Discrete-time sinusoid x[n]",
        xlabel="n (sample)",
        ylabel="x[n]",
    )
    _stem(ax2, n, r, title="Autocorrelation r[n]", xlabel="n (lag)", ylabel="r[n]")
    plt.show()


if __name__ == "__main__":
    # simple_auto_correlation_demo()
    main_mp4_audio_autocorr()

    