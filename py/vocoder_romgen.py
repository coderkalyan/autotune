"""Generate vocoder per-band ROMs for RTL.

Outputs:
    vocoder_rms_inv.mem       - per-band inverse-RMS gain with tilt
    vocoder_bp_s{0,1}_{coef}.mem  - 10 files, {coef} in {b0,b1,b2,a1,a2}

Each SOS cascade is 2 stages (butter order-2 bandpass). Per stage we emit
5 coefficients (a0 = 1 implied, dropped). 32 entries per ROM (one per band).
All entries Q3.24 fixed point, padded to 32-bit hex, one per line for
$readmemh.
"""

import numpy as np
from scipy.signal import butter, sosfilt
from tqdm import tqdm

# ---- configurable constants ----
FS_HZ = 48000
N_BANDS = 32
F_LO_HZ = 300.0
F_HI_HZ = 8000.0
BP_ORDER = 2
NOISE_LEN = FS_HZ * 20
SEED = 0xC0FFEE

# ---- Q3.24 fixed-point (27-bit signed, padded to 32) ----
Q_FRAC = 24
Q_WIDTH = 27
Q_MAX = (1 << (Q_WIDTH - 1)) - 1
Q_MIN = -(1 << (Q_WIDTH - 1))

RMS_OUT_PATH = "vocoder_rms_inv.mem"
BP_OUT_PREFIX = "vocoder_bp_"
BP_COEFF_NAMES = ["b0", "b1", "b2", "a1", "a2"]
BP_COEFF_SOS_IDX = {"b0": 0, "b1": 1, "b2": 2, "a1": 4, "a2": 5}  # skip a0=sos[3]
BP_N_STAGES = 2


def log_band_edges(n_bands: int, f_lo: float, f_hi: float) -> np.ndarray:
    return np.geomspace(f_lo, f_hi, n_bands + 1)


def float_to_q3_24(x: float) -> int:
    scaled = int(round(x * (1 << Q_FRAC)))
    sat = max(Q_MIN, min(Q_MAX, scaled))
    if sat < 0:
        sat += 1 << Q_WIDTH
    return sat


def band_edge_pair(i: int, edges: np.ndarray, fs: int) -> tuple[float, float]:
    f1 = float(edges[i])
    f2 = float(edges[i + 1])
    if f2 >= fs / 2:
        f2 = fs / 2 - 1.0
    return f1, f2


def design_band_sos(
    i: int, edges: np.ndarray, fs: int = FS_HZ, order: int = BP_ORDER
) -> np.ndarray | None:
    f1, f2 = band_edge_pair(i, edges, fs)
    print(f1, f2)
    if f1 >= f2:
        return None
    return butter(order, [f1, f2], btype="band", fs=fs, output="sos")


def compute_rms_inv_gains(
    fs: int = FS_HZ,
    n_bands: int = N_BANDS,
    f_lo: float = F_LO_HZ,
    f_hi: float = F_HI_HZ,
    order: int = BP_ORDER,
    noise_len: int = NOISE_LEN,
    seed: int = SEED,
) -> list[float]:
    edges = log_band_edges(n_bands, f_lo, f_hi)
    rng = np.random.default_rng(seed)
    white = rng.uniform(low=-1.0, high=1.0, size=noise_len)

    gains: list[float] = []
    for i in tqdm(range(n_bands)):
        bp_sos = design_band_sos(i, edges, fs, order)
        if bp_sos is None:
            gains.append(0.0)
            continue
        noise_band = sosfilt(bp_sos, white)
        rms = float(np.sqrt(np.mean(noise_band**2)))
        gain_x = (0.5 / 31) * i + 0.7
        gains.append((1.0 / rms) * gain_x)

    arr = np.array(gains)
    arr = arr / np.average(arr)
    return arr.tolist()


def compute_bp_coeffs(
    fs: int = FS_HZ,
    n_bands: int = N_BANDS,
    f_lo: float = F_LO_HZ,
    f_hi: float = F_HI_HZ,
    order: int = BP_ORDER,
) -> dict[tuple[int, str], list[float]]:
    """Return {(stage_idx, coef_name) -> [per-band values]}.

    Extracts raw SOS coefficients from butter() output exactly as generated;
    no filter logic change. For order=2 bandpass, bp_sos has shape (2, 6):
    [b0, b1, b2, a0, a1, a2] per section.
    """
    edges = log_band_edges(n_bands, f_lo, f_hi)
    coeffs: dict[tuple[int, str], list[float]] = {
        (s, k): [] for s in range(BP_N_STAGES) for k in BP_COEFF_NAMES
    }

    for i in range(n_bands):
        bp_sos = design_band_sos(i, edges, fs, order)
        for s in range(BP_N_STAGES):
            for k in BP_COEFF_NAMES:
                if bp_sos is None:
                    coeffs[(s, k)].append(0.0)
                else:
                    coeffs[(s, k)].append(float(bp_sos[s, BP_COEFF_SOS_IDX[k]]))

    return coeffs


def write_rom(path: str, values: list[float]) -> None:
    with open(path, "w") as f:
        for v in values:
            q = float_to_q3_24(v)
            f.write(f"{q:08x}\n")


if __name__ == "__main__":
    gains = compute_rms_inv_gains()
    for i, g in enumerate(gains):
        print(f"band {i:2d}: gain={g:.6f}")
    write_rom(RMS_OUT_PATH, gains)
    print(f"wrote {len(gains)} entries -> {RMS_OUT_PATH}")

    coeffs = compute_bp_coeffs()
    for s in range(BP_N_STAGES):
        for k in BP_COEFF_NAMES:
            path = f"{BP_OUT_PREFIX}s{s}_{k}.mem"
            vals = coeffs[(s, k)]
            write_rom(path, vals)
            vmax = max(abs(v) for v in vals)
            print(f"wrote {len(vals)} entries -> {path}  (|max|={vmax:.6f})")
