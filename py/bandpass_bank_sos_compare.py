import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import sosfilt
from vocoder2 import asymmetric_follower
import argparse


def make_saw(n: int, fs: int, f0: float) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / fs
    phase = (f0 * t) % 1.0
    return 2.0 * phase - 1.0

def main(use_follower: bool = False, attack_ms: float = 3.0, release_ms: float = 100.0):
    fs, n, f0 = 48_000, 4_800, 440

    # Hardware-style coefficient tables.
    b0 = np.array([0.10, 0.25, 0.50, 0.75], dtype=np.float64)
    a1 = np.array([-0.90, -0.75, -0.50, -0.25], dtype=np.float64)

    # SOS row format: [b0, b1, b2, a0, a1, a2]
    # Only b0 and a1 are non-zero; a0 is 1 by definition.
    sos = np.column_stack(
        [
            b0,
            np.zeros_like(b0),
            np.zeros_like(b0),
            np.ones_like(b0),
            a1,
            np.zeros_like(b0),
        ]
    )

    x = make_saw(n, fs, f0)
    y = [sosfilt(sos[i : i + 1], x) for i in range(len(b0))]

    if use_follower:
        y = [
            asymmetric_follower(np.abs(yi), fs, attack_ms=attack_ms, release_ms=release_ms)
            for yi in y
        ]

    print("SOS rows [b0, b1, b2, a0, a1, a2]:")
    print(sos)

    t = np.arange(n) / fs
    plt.figure(figsize=(12, 6))
    plt.plot(t, x, label="in (saw)", lw=1.2, color="k")
    mode = "y -> asymmetric_follower -> graph" if use_follower else "y -> graph"
    for i, yi in enumerate(y):
        plt.plot(t, yi, label=f"sos{i}: b0={b0[i]:.2f}, a1={a1[i]:.2f}")
    plt.title(mode)
    plt.xlim(0, 0.02)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    # parser = argparse.ArgumentParser(
    #     description="Compare 4 single-section SOS responses on a saw waveform."
    # )
    # parser.add_argument(
    #     "--use-follower",
    #     action="store_true",
    #     help="Apply asymmetric_follower(abs(y)) before plotting.",
    # )
    # parser.add_argument("--attack-ms", type=float, default=3.0)
    # parser.add_argument("--release-ms", type=float, default=100.0)
    # args = parser.parse_args()

    # main(
    #     use_follower=args.use_follower,
    #     attack_ms=args.attack_ms,
    #     release_ms=args.release_ms,
    # )
    main(
        use_follower=True,
        attack_ms=3,
        release_ms=100,
    )