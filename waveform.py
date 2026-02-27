import subprocess
import numpy as np
import matplotlib.pyplot as plt


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


def waveform(
    N: int,
    amplitude: float,
    f0_hz: float,
    fs_hz: float,
    num_harmonics: int,
    relative_amplitude: float,
    amplitude_decay: float,
    rng: np.random.Generator,
):
    n = np.arange(N, dtype=float)
    K = 1 + num_harmonics
    k = np.arange(1, 1 + K).reshape((1, K))
    A = amplitude / (k ** amplitude_decay)
    A[1:] *= relative_amplitude
    f_hz = f0_hz * k
    phase_rad = rng.uniform(0.0, 2.0 * np.pi, k.shape)

    n = n.reshape((N, 1)).repeat(K, axis=1)
    k = k.reshape((1, 1 + num_harmonics)).repeat(N, axis=0)
    omega_n = 2.0 * np.pi * (f_hz / fs_hz) * n + phase_rad

    return np.einsum('ij->i', A * np.cos(omega_n))


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
    mp4_path = r"10 Minutes of A Piano A4 440 Hz - Music in Space.mp3"  # TODO: hard-code your file path here

    # Keep this modest: r_of_n is O(N * max_lag) in your current implementation.
    # x, fs_hz = mp4_audio_to_signal(mp4_path=mp4_path, target_fs_hz=16_000, max_samples=65_536)
    fs_hz = int(48e3)
    start_s = 2.0
    end_s = start_s + 0.25
    x = a4_waveform(fs_hz, start_s, end_s)
    r = autocorrelation(x)

    max_lag = min(128, x.shape[0])
    print_period_first_peak(r, fs_hz=fs_hz, max_lag=max_lag)

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


def main_mp4_audio_chunked_period_tracking(
    *,
    duration_sec: float = 1_000_000.0,
    window_ms: float = 10.0,
    hop_ms: float = 2.5,
    target_fs_hz: int = 8_000,
) -> None:
    """Sliding-window pitch tracking via autocorr+peak detection; plot frequency vs time."""
    # mp4_path = r"10 Minutes of A Piano A4 440 Hz - Music in Space.mp3"  # TODO: hard-code your file path here
    mp4_path = r"Twinkle Twinkle Little Star - VERY EASY Piano tutorial for kids - The Grand Piano.mp3"  # TODO: hard-code your file path here

    x, fs_hz = mp4_audio_to_signal(
        mp4_path=mp4_path,
        target_fs_hz=int(target_fs_hz),
        start_time_sec=0.0,
        duration_sec=float(duration_sec),
        max_samples=20_000_000,
    )

    # Low-pass filter (cutoff = 4200 Hz)
    cutoff_hz = 4200.0
    nyq = 0.5 * fs_hz
    fc = min(cutoff_hz, 0.99 * nyq)
    if x.size and fc > 0:
        numtaps = 101
        n = np.arange(numtaps, dtype=float)
        m = (numtaps - 1) / 2.0
        h = (2.0 * fc / fs_hz) * np.sinc((2.0 * fc / fs_hz) * (n - m))
        h *= np.hamming(numtaps)
        h /= float(np.sum(h))
        x = np.convolve(x, h, mode="same")

    window_len = int(round((float(window_ms) * 1e-3) * fs_hz))
    hop_len = int(round((float(hop_ms) * 1e-3) * fs_hz))
    if window_len < 3 or hop_len < 1:
        raise ValueError("window_ms must be >= ~3 samples and hop_ms must be >= ~1 sample")

    times_sec: list[float] = []
    freq_hz: list[float] = []

    amp_threshold = 0.02  # signal is normalized to ~[-1, 1]

    for start in range(0, x.size - window_len + 1, hop_len):
        window = x[start : start + window_len]
        window = window - float(np.mean(window))
        times_sec.append((start + 0.5 * window_len) / fs_hz)

        if float(np.max(np.abs(window))) < amp_threshold:
            freq_hz.append(0.0)
            continue

        window = window * np.hanning(window_len)
        r = autocorrelation(window)
        _, peak_sec = estimate_period_first_peak(r, fs_hz=fs_hz, max_lag=min(128, window_len))
        if peak_sec is None:
            freq_hz.append(float("nan"))
        else:
            freq_hz.append(float(1.0 / peak_sec))

    import matplotlib.pyplot as plt

    hop_sec = hop_len / fs_hz
    win_len = max(1, int(round(0.1 / hop_sec)))
    y = np.asarray(freq_hz, dtype=float)

    half = win_len // 2
    y_pad = np.pad(
        y,
        (half, win_len - 1 - half),
        mode="constant",
        constant_values=np.nan,
    )
    try:
        windows = np.lib.stride_tricks.sliding_window_view(y_pad, win_len)
        y_med = np.nanmedian(windows, axis=1)
    except Exception:
        y_med = np.empty_like(y)
        for i in range(y.size):
            y_med[i] = np.nanmedian(y_pad[i : i + win_len])

    plt.figure(figsize=(10, 4), constrained_layout=True)
    plt.plot(times_sec, y_med, linewidth=0.8)
    plt.title(
        f"Estimated frequency over time (sliding autocorrelation, window={window_ms:g} ms, hop={hop_ms:g} ms)"
    )
    plt.xlabel("time (s)")
    plt.ylabel("frequency (Hz)")
    plt.grid(True, alpha=0.3)
    plt.show()


def autocorrelation(x: np.ndarray) -> np.ndarray:
    """Compute r(n) = sum_{k=0}^{N-n-1} x[k] * x[k+n] for n=0..N-1."""
    x = np.asarray(x)
    N = x.shape[0]
    r = np.zeros(N, dtype=np.result_type(x, np.float64))
    for n in range(N):
    # for n in range(N):
        # sum_{k=0}^{N-n-1} x[k]*x[k+n]
        r[n] = np.dot(x[: N - n], x[n:]) / N
    return r


def sliding_average_3(y: np.ndarray) -> np.ndarray:
    """3-point sliding average (N=3)."""
    y = np.asarray(y, dtype=float)
    if y.size < 3:
        return y.copy()
    out = y.copy()
    out[1:-1] = (y[:-2] + y[1:-1] + y[2:]) / 3.0
    return out


def first_peak_lag(y: np.ndarray) -> int | None:
    """Naive peak pick: first i>0 with y[i] >= neighbors and y[i] > 0."""
    y = np.asarray(y, dtype=float)
    if y.size < 3:
        return None
    for i in range(1, y.size - 1):
        if y[i] > 0 and y[i] >= y[i - 1] and y[i] >= y[i + 1]:
            return int(i)
    return None


def estimate_period_first_peak(
    r: np.ndarray, *, fs_hz: float | None = None, max_lag: int = 128
) -> tuple[int | None, float | None]:
    """Return (peak_lag_samples, peak_period_sec) using r[0:max_lag]."""
    r = np.asarray(r, dtype=float)
    max_lag = min(int(max_lag), r.size)
    r_ma = sliding_average_3(r[:max_lag])
    peak_lag = first_peak_lag(r_ma)
    if peak_lag is None or fs_hz is None:
        return peak_lag, None
    return peak_lag, float(peak_lag) / float(fs_hz)


def print_period_first_peak(r: np.ndarray, *, fs_hz: float, max_lag: int = 128) -> None:
    """Print the period until the first peak, ignoring the peak at T=0."""
    peak_lag, peak_sec = estimate_period_first_peak(r, fs_hz=fs_hz, max_lag=max_lag)
    if peak_lag is None:
        print("No peak found in autocorrelation (excluding T=0) within computed lags.")
        return
    if peak_sec is None:
        print(f"Estimated period (first peak, ignoring T=0): {peak_lag} samples")
        return
    print(f"Estimated period (first peak, ignoring T=0): {peak_lag} samples ({peak_sec:.6f} s = {1.0/peak_sec:.2f} Hz)")


def mock_waveform(fs_hz: int):
    duration_s = 0.01
    amplitude = 1
    snr = 10

    N = int(fs_hz * duration_s)
    notes = [(493.88, N // 2), (440.0, N), (493.88, N // 2)]
    rng = np.random.default_rng(0)

    waveforms = map(lambda note: waveform(
        note[1],
        amplitude=amplitude,
        f0_hz=note[0],
        fs_hz=fs_hz,
        num_harmonics=10,
        relative_amplitude=0.5,
        amplitude_decay=1,
        rng=rng,
    ), notes)

    x = np.hstack(list(waveforms))
    x += rng.normal(0.0, amplitude / snr, x.shape)
    return x


def a4_waveform(fs_hz: int, start_s: float, end_s: float):
    with open("a4.pcm", "rb") as f:
        buffer = f.read()
        x = np.frombuffer(buffer, dtype=np.float32)

    start = int(fs_hz * start_s)
    end = int(fs_hz * end_s)
    return x[start:end]


def single_autocorrelation():
    fs_hz = 48000

    x = mock_waveform(fs_hz)

    start_s = 2.0
    end_s = start_s + 0.25
    x = a4_waveform(fs_hz, start_s, end_s)

def simple_auto_correlation_demo():
    fs_hz = int(48e3)
    z = z * np.hanning(len(z))

    r = autocorrelation(z)

    max_lag = min(128, r.shape[0])
    print_period_first_peak(r, fs_hz=fs_hz, max_lag=max_lag)

    n = np.arange(len(z))
    _, (ax1, ax2) = plt.subplots(2, 1, figsize=(8, 6), constrained_layout=True)
    _stem(
        ax1,
        n,
        z,
        title="Discrete-time sinusoid x[n]",
        xlabel="n (sample)",
        ylabel="x[n]",
    )
    _stem(ax2, n, r, title="Autocorrelation r[n]", xlabel="n (lag)", ylabel="r[n]")
    plt.show()


if __name__ == "__main__":
    # simple_auto_correlation_demo()
    main_mp4_audio_autocorr()
    # main_mp4_audio_chunked_period_tracking()
