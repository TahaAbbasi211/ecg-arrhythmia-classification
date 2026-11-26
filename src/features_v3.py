"""Scale-invariant, patient-template, and local-rhythm ECG beat features (v3).

All calculations rely solely on plain NumPy/Python arithmetic (no scipy),
making the entire feature extractor 1:1 portable to Dart and JavaScript.
"""

import math

import numpy as np

FS = 360
PRE = 90
POST = 110
BEAT_LEN = PRE + POST  # 200 samples
R = PRE                # R-peak index inside a 200-sample beat window
EPS = 1e-8
LOCAL_RR_HALF_WIN = 15

# Clinical sub-windows inside the 200-sample beat window (at 360 Hz):
# - P-wave / PR interval: ~222 ms to ~56 ms before the R-peak
# - QRS complex: +/-83 ms around the R-peak
# - T-wave / ST segment: ~69 ms to ~278 ms after the R-peak
P_START, P_END = R - 80, R - 20      # [10 : 70]
QRS_START, QRS_END = R - 30, R + 30  # [60 : 120]
T_START, T_END = R + 25, R + 100     # [115 : 190]

RHYTHM_NAMES = (
    "prev_rr_s",
    "next_rr_s",
    "local_med_rr_s",
    "prev_rr_rel",
    "next_rr_rel",
    "comp_pause_ratio",
    "rr_ratio",
    "rr_asym",
    "prev_to_prev2",
    "next_to_next2",
    "prev2_rel",
    "next2_rel",
    "local_iqr_rel",
    "prematurity_z",
)

MORPH_SCALAR_NAMES = (
    "amp_r",
    "peak",
    "trough",
    "p2p",
    "t_peak",
    "t_trough",
    "width",
    "energy",
    "area",
    "sd",
    "sk",
    "ku",
)

SHAPE_NAMES = tuple(f"shape_{i:02d}" for i in range(40))

TEMPLATE_NAMES = (
    "corr_p",
    "rms_diff_p",
    "corr_qrs",
    "rms_diff_qrs",
    "corr_t",
    "rms_diff_t",
    "corr_full",
    "rms_diff_full",
    "corr_qrs_minus_p",
)

PT_WAVE_NAMES = (
    "energy_p_qrs_ratio",
    "energy_t_qrs_ratio",
    "p_max",
    "p_min",
    "p_peak_pos",
    "p_max_diff_tpl",
    "p_min_diff_tpl",
    "t_max",
    "t_max_diff_tpl",
)

FEATURE_NAMES = RHYTHM_NAMES + MORPH_SCALAR_NAMES + SHAPE_NAMES + TEMPLATE_NAMES + PT_WAVE_NAMES

FEATURE_GROUPS = {
    "rhythm": slice(0, len(RHYTHM_NAMES)),
    "morph": slice(len(RHYTHM_NAMES), len(RHYTHM_NAMES) + len(MORPH_SCALAR_NAMES) + len(SHAPE_NAMES)),
    "template": slice(
        len(RHYTHM_NAMES) + len(MORPH_SCALAR_NAMES) + len(SHAPE_NAMES),
        len(RHYTHM_NAMES) + len(MORPH_SCALAR_NAMES) + len(SHAPE_NAMES) + len(TEMPLATE_NAMES),
    ),
    "pt_wave": slice(
        len(RHYTHM_NAMES) + len(MORPH_SCALAR_NAMES) + len(SHAPE_NAMES) + len(TEMPLATE_NAMES),
        len(FEATURE_NAMES),
    ),
}

FEATURE_INDEX = {name: idx for idx, name in enumerate(FEATURE_NAMES)}


def _quantile_sorted(sorted_vals, q):
    """Compute a linear-interpolation quantile on a pre-sorted 1D sequence."""
    m = len(sorted_vals)
    if m == 0:
        return 0.0
    if m == 1:
        return float(sorted_vals[0])
    pos = q * (m - 1)
    lo = int(math.floor(pos))
    hi = min(lo + 1, m - 1)
    frac = pos - lo
    return float(sorted_vals[lo] * (1.0 - frac) + sorted_vals[hi] * frac)


def compute_recording_scale(beats):
    """Compute robust recording amplitude scale and scale-normalized centered beats.

    Each beat is centered by its own median, then divided by the recording-wide
    median peak-to-peak amplitude (floored at EPS). Because all downstream
    amplitude and morphology features use `x_rec`, multiplying the entire input
    signal by any positive constant (e.g. 0.001 for V or 1000 for uV) leaves
    `x_rec` and every feature invariant while preserving intra-recording
    amplitude differences such as larger PVCs.
    """
    arr = np.asarray(beats, dtype=np.float64)
    if arr.ndim != 2 or arr.shape[1] != BEAT_LEN:
        raise ValueError(f"expected beats with shape (N, {BEAT_LEN}), got {arr.shape}")
    if arr.shape[0] == 0:
        return 1.0, np.zeros((0, BEAT_LEN), dtype=np.float64)

    x_centered = arr - np.median(arr, axis=1, keepdims=True)
    p2p_raw = x_centered.max(axis=1) - x_centered.min(axis=1)
    med_p2p = float(np.median(p2p_raw))
    rec_scale = med_p2p if med_p2p > EPS else EPS
    x_rec = x_centered / rec_scale
    return rec_scale, x_rec


def compute_recording_template(x_rec):
    """Build an element-wise median beat template across a recording's beats."""
    arr = np.asarray(x_rec, dtype=np.float64)
    if arr.ndim != 2 or arr.shape[1] != BEAT_LEN:
        raise ValueError(f"expected x_rec with shape (N, {BEAT_LEN}), got {arr.shape}")
    if arr.shape[0] == 0:
        return np.zeros(BEAT_LEN, dtype=np.float64)
    return np.median(arr, axis=0)


def compute_compensatory_pause_ratio(prev_rr, next_rr, local_med_rr):
    """Return (prev_rr + next_rr) / max(2 * local_med_rr, EPS)."""
    return float(prev_rr + next_rr) / max(2.0 * float(local_med_rr), EPS)


def _local_rhythm_features(rr, fs=FS, half_win=LOCAL_RR_HALF_WIN):
    """Compute 14 local-window R-R features robust to short (10-60 s) recordings."""
    n = len(rr)
    out = np.zeros((n, len(RHYTHM_NAMES)), dtype=np.float64)
    if n == 0:
        return out

    prev_rr = np.maximum(np.asarray(rr[:, 0], dtype=np.float64), 0.0)
    next_rr = np.maximum(np.asarray(rr[:, 1], dtype=np.float64), 0.0)

    for i in range(n):
        lo = max(0, i - half_win)
        hi = min(n, i + half_win + 1)
        win_sorted = sorted(float(v) for v in prev_rr[lo:hi])
        local_med = _quantile_sorted(win_sorted, 0.5)
        local_iqr = _quantile_sorted(win_sorted, 0.75) - _quantile_sorted(win_sorted, 0.25)

        p_i = float(prev_rr[i])
        n_i = float(next_rr[i])
        p2_i = float(prev_rr[i - 1]) if i > 0 else p_i
        n2_i = float(next_rr[i + 1]) if i + 1 < n else n_i

        safe_med = max(local_med, EPS)
        out[i, 0] = p_i / fs
        out[i, 1] = n_i / fs
        out[i, 2] = local_med / fs
        out[i, 3] = p_i / safe_med
        out[i, 4] = n_i / safe_med
        out[i, 5] = compute_compensatory_pause_ratio(p_i, n_i, local_med)
        out[i, 6] = p_i / max(n_i, EPS)
        out[i, 7] = (n_i - p_i) / max(p_i + n_i, EPS)
        out[i, 8] = p_i / max(p2_i, EPS)
        out[i, 9] = n_i / max(n2_i, EPS)
        out[i, 10] = p2_i / safe_med
        out[i, 11] = n2_i / safe_med
        out[i, 12] = local_iqr / safe_med
        out[i, 13] = (p_i - local_med) / max(local_iqr, 0.05 * local_med, EPS)

    return out


def _morph_features(x_rec):
    """Compute 52 scale-invariant single-beat morphology features on `x_rec`."""
    n = x_rec.shape[0]
    if n == 0:
        return np.zeros((0, len(MORPH_SCALAR_NAMES) + len(SHAPE_NAMES)), dtype=np.float64)

    peak = x_rec.max(axis=1)
    trough = x_rec.min(axis=1)
    p2p = peak - trough
    amp_r = x_rec[:, R]
    t_peak = x_rec.argmax(axis=1) - R
    t_trough = x_rec.argmin(axis=1) - R

    thr = 0.3 * np.abs(x_rec).max(axis=1, keepdims=True)
    width = (np.abs(x_rec[:, R - 40:R + 40]) > thr).sum(axis=1)

    energy = (x_rec * x_rec).sum(axis=1)
    area = np.abs(x_rec).sum(axis=1)

    dev = x_rec - x_rec.mean(axis=1, keepdims=True)
    m2 = (dev * dev).mean(axis=1)
    m3 = (dev * dev * dev).mean(axis=1)
    m4 = (dev * dev * dev * dev).mean(axis=1)
    sd = np.sqrt(m2)
    flat = m2 <= 1e-12
    safe_m2 = np.where(flat, 1.0, m2)
    sk = np.where(flat, 0.0, m3 / (safe_m2 ** 1.5))
    ku = np.where(flat, 0.0, m4 / (safe_m2 * safe_m2) - 3.0)

    shape = x_rec[:, ::5] / (p2p[:, None] + EPS)

    return np.column_stack([
        amp_r, peak, trough, p2p, t_peak, t_trough,
        width, energy, area, sd, sk, ku, shape,
    ])


def _segment_corr_and_rms(seg, tpl_seg):
    """Vectorized Pearson correlation and RMS difference against a 1D template segment."""
    n = seg.shape[0]
    diff = seg - tpl_seg[None, :]
    rms = np.sqrt(np.mean(diff * diff, axis=1))

    da = seg - seg.mean(axis=1, keepdims=True)
    db = tpl_seg - float(np.mean(tpl_seg))
    va = (da * da).sum(axis=1)
    vb = float(np.dot(db, db))
    denom = np.sqrt(va * vb)
    corr = np.zeros(n, dtype=np.float64)
    valid = denom > 1e-12
    if np.any(valid):
        corr[valid] = np.clip((da[valid] @ db) / denom[valid], -1.0, 1.0)
    return corr, rms


def _template_and_pt_features(x_rec, template):
    """Compute 9 template-comparison features and 9 P/T regional features."""
    n = x_rec.shape[0]
    if n == 0:
        return (
            np.zeros((0, len(TEMPLATE_NAMES)), dtype=np.float64),
            np.zeros((0, len(PT_WAVE_NAMES)), dtype=np.float64),
        )

    seg_p = x_rec[:, P_START:P_END]
    seg_qrs = x_rec[:, QRS_START:QRS_END]
    seg_t = x_rec[:, T_START:T_END]

    tpl_p = template[P_START:P_END]
    tpl_qrs = template[QRS_START:QRS_END]
    tpl_t = template[T_START:T_END]

    corr_p, rms_p = _segment_corr_and_rms(seg_p, tpl_p)
    corr_qrs, rms_qrs = _segment_corr_and_rms(seg_qrs, tpl_qrs)
    corr_t, rms_t = _segment_corr_and_rms(seg_t, tpl_t)
    corr_full, rms_full = _segment_corr_and_rms(x_rec, template)

    tpl_out = np.column_stack([
        corr_p, rms_p, corr_qrs, rms_qrs, corr_t, rms_t, corr_full, rms_full,
        corr_qrs - corr_p,
    ])

    e_p = (seg_p * seg_p).sum(axis=1)
    e_qrs = (seg_qrs * seg_qrs).sum(axis=1)
    e_t = (seg_t * seg_t).sum(axis=1)

    p_max = seg_p.max(axis=1)
    p_min = seg_p.min(axis=1)
    p_peak_pos = (P_START + seg_p.argmax(axis=1) - R).astype(np.float64)
    t_max = seg_t.max(axis=1)

    pt_out = np.column_stack([
        e_p / (e_qrs + EPS),
        e_t / (e_qrs + EPS),
        p_max,
        p_min,
        p_peak_pos,
        p_max - float(np.max(tpl_p)),
        p_min - float(np.min(tpl_p)),
        t_max,
        t_max - float(np.max(tpl_t)),
    ])
    return tpl_out, pt_out


def extract_recording_features_v3(beats, rr, fs=FS):
    """Extract the 84-column v3 feature matrix for a single recording/clip.

    Parameters
    ----------
    beats : array-like, shape (N, 200)
        Chronologically ordered beat windows centered at R = 90.
    rr : array-like, shape (N, 2)
        Neighbouring R-R intervals `(prev_rr, next_rr)` in 360 Hz samples.
    fs : int or float, default 360
        Sampling rate used to convert R-R intervals into seconds.
    """
    arr = np.asarray(beats, dtype=np.float64)
    rr_arr = np.asarray(rr, dtype=np.float64)
    if arr.ndim != 2 or arr.shape[1] != BEAT_LEN:
        raise ValueError(f"expected beats with shape (N, {BEAT_LEN}), got {arr.shape}")
    if rr_arr.ndim != 2 or rr_arr.shape != (arr.shape[0], 2):
        raise ValueError(f"expected rr with shape ({arr.shape[0]}, 2), got {rr_arr.shape}")
    if arr.shape[0] == 0:
        return np.zeros((0, len(FEATURE_NAMES)), dtype=np.float64)

    _, x_rec = compute_recording_scale(arr)
    template = compute_recording_template(x_rec)
    rhythm = _local_rhythm_features(rr_arr, fs=fs)
    morph = _morph_features(x_rec)
    tpl, pt_wave = _template_and_pt_features(x_rec, template)
    return np.hstack([rhythm, morph, tpl, pt_wave])


def build_features_v3(X, rr, g, fs=FS):
    """Build v3 feature matrix across multiple recordings/clips grouped by `g`.

    Each unique group in `g` is processed independently in row order so there is
    zero cross-recording or cross-patient leakage.
    """
    X_arr = np.asarray(X, dtype=np.float64)
    rr_arr = np.asarray(rr, dtype=np.float64)
    g_arr = np.asarray(g)
    n = X_arr.shape[0]
    if n == 0:
        return np.zeros((0, len(FEATURE_NAMES)), dtype=np.float64)
    if rr_arr.shape != (n, 2):
        raise ValueError(f"expected rr with shape ({n}, 2), got {rr_arr.shape}")
    if g_arr.shape != (n,):
        raise ValueError(f"expected g with shape ({n},), got {g_arr.shape}")

    out = np.zeros((n, len(FEATURE_NAMES)), dtype=np.float64)
    for rec in np.unique(g_arr):
        idx = np.flatnonzero(g_arr == rec)
        out[idx] = extract_recording_features_v3(X_arr[idx], rr_arr[idx], fs=fs)
    return out
