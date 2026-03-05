import numpy as np
import matplotlib.pyplot as plt

from util import _stem, waveform


def autocorrelation(x: np.ndarray) -> np.ndarray:
    """Compute r(n) = sum_{k=0}^{N-n-1} x[k] * x[k+n] for n=0..N-1."""
    x = np.asarray(x)
    N = x.shape[0]
    r = np.zeros(N, dtype=np.result_type(x, np.float64))
    for n in range(N):
        # sum_{k=0}^{N-n-1} x[k]*x[k+n]
        r[n] = np.dot(x[: N - n], x[n:]) / N

    return r


def remove_noise(x: np.ndarray, clip_ratio:float = 0.30) -> np.ndarray:
    """Center-clipper noise reduction (symmetric).

    Let Amax be the maximum absolute amplitude of the signal and CL be the
    clipping level (a fixed percentage of Amax). Samples whose magnitude is
    below CL are set to 0; samples beyond CL are reduced by CL toward 0.

    Using CL = 0.30 * Amax:

        y[n] = x[n] - CL   for x[n] >  CL
        y[n] = 0           for |x[n]| <= CL
        y[n] = x[n] + CL   for x[n] < -CL

    Output has the same length as the input.
    """
    x = np.asarray(x)
    if x.size == 0:
        return x.copy()

    N = x.shape[0]
    y = np.zeros(N, dtype=np.result_type(x, np.float64))

    amax = float(np.max(np.abs(x)))
    # clip_ratio = 0.30
    CL = clip_ratio * amax

    for n in range(N):
        xn = x[n]
        if xn > CL:
            y[n] = xn - CL
        elif xn < -CL:
            y[n] = xn + CL
        else:
            y[n] = 0

    return y

def moving_average_3(x: np.ndarray) -> np.ndarray:
    """3-sample moving average FIR filter (causal).

    Computes:
        y[n] = (x[n] + x[n-1] + x[n-2]) / 3

    For n < 0 terms, x[...] is treated as 0 (i.e., zero-padding).
    Output has the same length as the input.
    """
    x = np.asarray(x)
    N = x.shape[0]
    y = np.zeros(N, dtype=np.result_type(x, np.float64))

    for n in range(N):
        acc = y.dtype.type(0)
        acc += x[n]
        if n - 1 >= 0:
            acc += x[n - 1]
        if n - 2 >= 0:
            acc += x[n - 2]
        y[n] = acc / 3

    return y


def alpha_calculation(fc_hz: float, fs_hz: float) -> float:
    """Compute the 1st-order IIR LPF smoothing factor.

    Uses: alpha = (2*pi*fc/fs) / (1 + 2*pi*fc/fs)
    """
    if fs_hz <= 0:
        raise ValueError("fs_hz must be > 0")
    if fc_hz < 0:
        raise ValueError("fc_hz must be >= 0")

    x = 2.0 * np.pi * (fc_hz / fs_hz)
    alpha = float(x / (1.0 + x))
    # Numerical safety: keep within [0, 1]
    return float(np.clip(alpha, 0.0, 1.0))


def low_pass_filter(data: np.ndarray, alpha: float) -> np.ndarray:
    """Applies a first-order IIR low-pass filter.

    alpha: smoothing factor (0 to 1)
    """
    data = np.asarray(data)
    if data.size == 0:
        return data.copy()

    y = np.zeros_like(data)
    y[0] = data[0]  # Initialize with the first data point

    for n in range(1, len(data)):
        y[n] = alpha * data[n] + (1 - alpha) * y[n - 1]

    return y


def low_pass_filter_2(data: np.ndarray, alpha: float) -> np.ndarray:
    """Applies a second-order IIR low-pass filter.

    This is implemented as two cascaded first-order sections (i.e., apply the
    1st-order `low_pass_filter` twice), which yields an overall 2nd-order LPF.

    alpha: smoothing factor (0 to 1)
    """
    data = np.asarray(data)
    if data.size == 0:
        return data.copy()

    y = low_pass_filter(data, alpha)
    y = low_pass_filter(y, alpha)
    return y


def high_pass_filter(data: np.ndarray, alpha: float) -> np.ndarray:
    """Applies a first-order IIR high-pass filter.

    Uses the standard discrete-time 1st-order HPF form:

        y[n] = alpha * (y[n-1] + x[n] - x[n-1])

    where alpha is a smoothing factor in [0, 1]. Values closer to 1 produce a
    gentler (lower-cutoff) high-pass; values closer to 0 produce a more
    aggressive (higher-cutoff) high-pass.
    """
    data = np.asarray(data)
    if data.size == 0:
        return data.copy()

    y = np.zeros_like(data)
    # Common initialization for HPF: start at 0 to avoid a large transient.
    y[0] = 0

    for n in range(1, len(data)):
        y[n] = alpha * (y[n - 1] + data[n] - data[n - 1])

    return y


def high_pass_filter_2(data: np.ndarray, alpha: float) -> np.ndarray:
    """Applies a second-order IIR high-pass filter.

    This is implemented as two cascaded first-order sections (i.e., apply the
    1st-order `high_pass_filter` twice), which yields an overall 2nd-order HPF.

    alpha: smoothing factor (0 to 1)
    """
    data = np.asarray(data)
    if data.size == 0:
        return data.copy()

    y = high_pass_filter(data, alpha)
    y = high_pass_filter(y, alpha)
    return y


def peak(x: np.ndarray, max_lag: int) -> int | None:
    # ignore lag=0 peak
    start = 200 
    alpha = 0.2
    threshold = alpha * x[0]
    x = x[start:max_lag]

    if x.size < 3:
        return None

    # calculate local maxima (for positive values)
    left = x[:-2]
    center = x[1:-1]
    right = x[2:]
    maxima = np.logical_and(left < center, center > right)
    maxima = np.logical_and(maxima, center > 0)
    maxima = np.logical_and(maxima, center > threshold)

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


def plot_fft(
    z: np.ndarray,
    fs_hz: float = 48000.0,
    title: str | None = None,
) -> None:
    """Compute and plot the FFT magnitude of a 1-D signal.

    - Uses a Hann window + mean removal to reduce spectral leakage.
    - Plots the single-sided magnitude spectrum in dB.
    - No return value (plot only).
    """
    z = np.asarray(z)
    if z.size == 0:
        raise ValueError("z must be non-empty")
    if z.ndim != 1:
        z = z.reshape(-1)

    if fs_hz <= 0:
        raise ValueError("fs_hz must be > 0")

    z = z.astype(np.float64, copy=False)
    z = z - float(np.mean(z))
    window = np.hanning(z.size)
    z_win = z * window

    Z = np.fft.rfft(z_win)
    freqs_hz = np.fft.rfftfreq(z.size, d=1.0 / fs_hz)

    mag_db = 20.0 * np.log10(np.abs(Z) + 1e-12)

    if title is None:
        title = "FFT magnitude"

    plt.figure(figsize=(10, 4), constrained_layout=True)
    plt.plot(freqs_hz, mag_db, linewidth=0.8)
    plt.title(f"{title} (N={z.size}, fs={fs_hz:g} Hz)")
    plt.xlabel("frequency (Hz)")
    plt.ylabel("magnitude (dB)")
    plt.grid(True, alpha=0.3)
    plt.xlim(0, fs_hz / 2)
    plt.show()


def single_autocorrelation():
    fs_hz = 48000

    # z = mock_waveform(fs_hz)

    # start_s = 2.0
    # end_s = start_s + 0.25
    # z = pcm_waveform("a4.pcm", fs_hz, start_s, end_s)

    # z = pcm_waveform("py/twinkle.pcm", fs_hz, 4.62, 4.64)
    # z = pcm_waveform("py/yoasobi.pcm", fs_hz, start_s=52, end_s=52.5)
    # z = pcm_waveform("py/DAZBEE.pcm", fs_hz, start_s=30, end_s=30.5)
    # z = pcm_waveform("py/DAZBEE_Acapella.pcm", fs_hz, start_s=22.5, end_s=22.52)
    # plot_fft(z, fs_hz=fs_hz, title="PCM segment FFT (raw)")
    z = remove_noise(z)


    # Low-pass filter the PCM waveform
    fc_hz = 1300
    alpha = alpha_calculation(fc_hz=fc_hz, fs_hz=fs_hz)

    fc_hz = 200
    beta = alpha_calculation(fc_hz=fc_hz, fs_hz=fs_hz)
    # z = z * np.hanning(len(z))
    # z_filt = high_pass_filter(z_filt, beta)
    z_filt = low_pass_filter_2(z, alpha)
    plot_fft(z_filt, fs_hz=fs_hz, title="PCM segment FFT (raw)")

    # z = z * np.hanning(len(z))

    r = autocorrelation(z_filt)
    # r = autocorrelation(z)
    # r = moving_average_3(r)
    max_lag = len(r)
    peak_n = peak(r, max_lag)
    print(peak_n)
    if peak_n is None:
        print("No peak found in autocorrelation within bounds.")
    else:
        f0_hz = fs_hz / peak_n
        print(f"Estimated f0 = {f0_hz:.2f} Hz (peak lag = {peak_n} samples)")

    n = np.arange(len(z))
    _, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(9, 8), constrained_layout=True)
    ax1.plot(n, z, linewidth=0.8)
    ax1.set_title("PCM waveform (before low-pass)")
    ax1.set_xlabel("n (sample)")
    ax1.set_ylabel("amplitude")
    ax1.grid(True, alpha=0.3)

    ax2.plot(n, z_filt, linewidth=0.8)
    ax2.set_title(f"PCM waveform (after low-pass, fc={fc_hz:g} Hz, alpha={alpha:.4f})")
    ax2.set_xlabel("n (sample)")
    ax2.set_ylabel("amplitude")
    ax2.grid(True, alpha=0.3)

    _stem(ax3, n, r, title="Autocorrelation r[n] (filtered)", xlabel="n (lag)", ylabel="r[n]")
    # out_path = "py/single_autocorrelation.png"
    # plt.savefig(out_path, dpi=150)
    # print(f"Saved plot to {out_path}")
    plt.show()


def multi_autocorrelation():
    fs_hz = 48000
    window_size = 1024
    stride = window_size//4
    # stride = 256
    fc_hz = 1300
    alpha = 1 - np.exp(-2.0 * np.pi * fc_hz / fs_hz)
    # z = pcm_waveform("py/yoasobi.pcm", fs_hz, start_s=52, end_s=53)
    # z = pcm_waveform("py/DAZBEE_Acapella.pcm", fs_hz, start_s=22, end_s=23)
    # z = pcm_waveform("py/DAZBEE.pcm", fs_hz, start_s=25, end_s=30)
    
    z = pcm_waveform("py/twinkle.pcm", fs_hz, start_s=2.0, end_s=12.0)
    # z = pcm_waveform("twinkle.pcm", fs_hz, start_s=0.0, end_s=60)
    # z = pcm_waveform("tides.pcm", fs_hz, start_s=5.0, end_s=15.0)

    # alpha1 = alpha_calculation(fc_hz=fc_hz, fs_hz=fs_hz)
    # z = z * np.hanning(len(z))
    z = low_pass_filter_2(z, alpha_calculation(fc_hz=300, fs_hz=fs_hz))
    # z = high_pass_filter_2(z, alpha_calculation(fc_hz=100, fs_hz=fs_hz))

    print("z:", len(z))
    assert window_size % stride == 0
    f0s = [0.0]
    for start in range(0, len(z) - window_size + 1, stride):
        window = z[start:start + window_size]
        window = window * np.hanning(window_size)
        window = remove_noise(window, clip_ratio=.3)
        r = autocorrelation(window)
        peak_n = peak(r, len(r))
        if peak_n is None or peak_n < int(fs_hz / 2000):
            f0_hz = f0s[-1]
        else:
            f0_hz = fs_hz / peak_n

        # f0_hz = f0s[-1] + alpha * (f0_hz - f0s[-1])*5
        f0s.append(f0_hz)

    f0s = low_pass_filter_2(np.array(f0s, dtype=float), alpha_calculation(fc_hz=1000, fs_hz=fs_hz))
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
