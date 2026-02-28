import subprocess
import numpy as np
import matplotlib.pyplot as plt
from numpy.lib.stride_tricks import sliding_window_view


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


def autocorrelation(x: np.ndarray) -> np.ndarray:
    """Compute r(n) = sum_{k=0}^{N-n-1} x[k] * x[k+n] for n=0..N-1."""
    x = np.asarray(x)
    N = x.shape[0]
    r = np.zeros(N, dtype=np.result_type(x, np.float64))
    for n in range(N):
        # sum_{k=0}^{N-n-1} x[k]*x[k+n]
        r[n] = np.dot(x[: N - n], x[n:]) / N

    return r


def peak(x: np.ndarray, max_lag: int) -> int | None:
    # ignore lag=0 peak
    start = 5
    alpha = 0.65
    threshold = alpha * x[0]
    x = x[start:max_lag]

    # calculate local maxima (for positive values)
    l = x[:-2]
    c = x[1:-1]
    r = x[2:]
    maxima = np.logical_and(l < c, c > r)
    maxima = np.logical_and(maxima, c > 0)
    maxima = np.logical_and(maxima, c > threshold)

    # find first maxima, accounting for offset
    period_n = np.argwhere(maxima) + 1 + start
    return None if len(period_n) == 0 else period_n[0][0]


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


def pcm_waveform(filename: str, fs_hz: int, start_s: float, end_s: float):
    with open(filename, "rb") as f:
        buffer = f.read()
        x = np.frombuffer(buffer, dtype=np.float32)

    start = int(fs_hz * start_s)
    end = int(fs_hz * end_s)
    return x[start:end]


def single_autocorrelation():
    fs_hz = 48000

    # z = mock_waveform(fs_hz)

    # start_s = 2.0
    # end_s = start_s + 0.25
    # z = pcm_waveform("a4.pcm", fs_hz, start_s, end_s)

    z = pcm_waveform("twinkle.pcm", fs_hz, 4.62, 4.64)

    # z = z * np.hanning(len(z))

    r = autocorrelation(z)
    max_lag = len(r)
    peak_n = peak(r, max_lag)
    if peak_n is None:
        print("No peak found in autocorrelation within bounds.")
    else:
        f0_hz = fs_hz / peak_n
        print(f"Estimated f0 = {f0_hz:.2f} Hz (peak lag = {peak_n} samples)")

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


def multi_autocorrelation():
    fs_hz = 48000
    window_size = 1024
    stride = 256
    fc_hz = 10000
    alpha = 1 - np.exp(-2.0 * np.pi * fc_hz / fs_hz)
    z = pcm_waveform("twinkle.pcm", fs_hz, start_s=2.0, end_s=12.0)
    # z = pcm_waveform("twinkle.pcm", fs_hz, start_s=0.0, end_s=60)
    # z = pcm_waveform("tides.pcm", fs_hz, start_s=5.0, end_s=15.0)

    assert window_size % stride == 0
    f0s = [0.0]
    for start in range(0, len(z) - window_size + 1, stride):
        window = z[start:start + window_size]
        window = window * np.hanning(window_size)
        r = autocorrelation(window)
        peak_n = peak(r, len(r))
        if peak_n is None or peak_n < int(fs_hz / 2000):
            f0_hz = f0s[-1]
        else:
            f0_hz = fs_hz / peak_n

        f0_hz = f0s[-1] + alpha * (f0_hz - f0s[-1])
        f0s.append(f0_hz)

    f0s = f0s[1:]
    # print(f0s)

    times = np.arange(0, len(z) - window_size + 1, stride) / fs_hz
    window_ms = (window_size / fs_hz) * 1e3
    plt.figure(figsize=(10, 4), constrained_layout=True)
    plt.plot(times, f0s, linewidth=0.8)
    plt.title(
        f"Estimated frequency over time (sliding autocorrelation, window={window_ms:g} ms)"
    )
    plt.xlabel("time (s)")
    plt.ylabel("frequency (Hz)")
    plt.grid(True, alpha=0.3)
    plt.show()

if __name__ == "__main__":
    # single_autocorrelation()
    multi_autocorrelation()
