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
