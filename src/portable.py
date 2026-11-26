"""Portable signal processing (numpy only, simple loops) so the same logic can be ported to Dart.

Only the filter coefficients (SOS) are generated with scipy; every function here uses
plain numpy / python so that each step can be re-implemented 1:1 on a phone.
"""
import math

import numpy as np

FS = 360

# --- input hygiene -----------------------------------------------------------
MIN_SAMPLES = 5              # anything shorter than this cannot hold a heartbeat
MAX_BAD_FRACTION = 0.05      # reject a file with more than 5% NaN / Inf samples
MAX_BAD_GAP_SECONDS = 0.5    # ... or with one corrupt run longer than this
FS_EPS = 1e-6                # |fs - 360| < FS_EPS means "already at the target rate"
TARGET_FS = FS
AA_CUTOFF = 150.0            # anti-aliasing low-pass corner, Hz
AA_ORDER = 3                 # Butterworth order of that pre-filter


class SignalError(ValueError):
    """A signal that cannot be analyzed: empty, too short, too corrupt or a bad rate."""


def check_sample_rate(fs):
    """Return [fs] as a float, or raise SignalError when it is not a usable rate."""
    try:
        value = float(fs)
    except (TypeError, ValueError):
        raise SignalError("sampling rate must be a number, got %r" % (fs,)) from None
    if not np.isfinite(value) or value <= 0:
        raise SignalError("sampling rate must be a positive number, got %r" % (fs,))
    return value


def make_sos():
    """Generate the two band-pass filters (scipy is only used here, not at runtime)."""
    from scipy.signal import butter
    sos_main = butter(3, [0.5, 40], btype="band", fs=FS, output="sos")   # signal for the model
    sos_det = butter(2, [5, 15], btype="band", fs=FS, output="sos")      # signal for R-peak detection
    return sos_main, sos_det


def sosfilt(sos, x):
    """Cascade of biquads, direct form II transposed, zero initial state."""
    y = np.asarray(x, dtype=float)
    for b0, b1, b2, a0, a1, a2 in sos:
        out = np.empty_like(y)
        z1 = 0.0
        z2 = 0.0
        for n in range(len(y)):
            v = y[n]
            o = b0 * v + z1
            z1 = b1 * v - a1 * o + z2
            z2 = b2 * v - a2 * o
            out[n] = o
        y = out
    return y


def filtfilt(sos, x, padlen=720):
    """Zero-phase filtering: odd-extend both ends, filter forward then backward, trim."""
    x = np.asarray(x, dtype=float)
    n = min(padlen, len(x) - 1)
    left = 2 * x[0] - x[n:0:-1]
    right = 2 * x[-1] - x[-2:-(n + 2):-1]
    y = np.concatenate([left, x, right])
    y = sosfilt(sos, y)
    y = sosfilt(sos, y[::-1])[::-1]
    return y[n:len(y) - n]


def butterworth_lowpass_sos(fs, cutoff=AA_CUTOFF, order=AA_ORDER):
    """Low-pass Butterworth as biquad sections, from the bilinear transform.

    Scipy is not needed (and is not available in Dart), so the sections are built
    from the classic analogue prototype: an odd order gets one first-order section
    plus pairs whose Q = 1 / (2 sin(pi (2k+1) / 2N)). Every section has unity gain
    at DC, so a signal in mV stays in mV.
    """
    fs = check_sample_rate(fs)
    if order < 1:
        raise ValueError("order must be >= 1")
    if not 0 < cutoff < fs / 2:
        raise ValueError("cutoff must be between 0 and the Nyquist frequency")

    sections = []
    if order % 2 == 1:
        k = math.tan(math.pi * cutoff / fs)
        b0 = k / (1.0 + k)
        sections.append([b0, b0, 0.0, 1.0, (k - 1.0) / (1.0 + k), 0.0])

    w0 = 2.0 * math.pi * cutoff / fs
    cos_w = math.cos(w0)
    sin_w = math.sin(w0)
    for i in range(order // 2):
        q = 1.0 / (2.0 * math.sin(math.pi * (2 * i + 1) / (2.0 * order)))
        alpha = sin_w / (2.0 * q)
        a0 = 1.0 + alpha
        sections.append([
            (1.0 - cos_w) / 2.0 / a0,
            (1.0 - cos_w) / a0,
            (1.0 - cos_w) / 2.0 / a0,
            1.0,
            -2.0 * cos_w / a0,
            (1.0 - alpha) / a0,
        ])
    return np.array(sections, dtype=float)


def sanitize_signal(x, fs, min_length=MIN_SAMPLES,
                    max_bad_fraction=MAX_BAD_FRACTION,
                    max_bad_gap_seconds=MAX_BAD_GAP_SECONDS):
    """Validate a raw signal and linearly interpolate scattered NaN / Inf samples.

    Raises SignalError (never returns a broken array) when the signal is empty or
    shorter than [min_length], when more than [max_bad_fraction] of its samples are
    NaN/Inf, or when one corrupt run lasts longer than [max_bad_gap_seconds].
    """
    fs = check_sample_rate(fs)
    arr = np.asarray(x, dtype=float).ravel()
    if arr.size < min_length:
        raise SignalError(
            "signal is too short (%d samples, at least %d needed)" % (arr.size, min_length))

    bad = ~np.isfinite(arr)
    n_bad = int(bad.sum())
    if n_bad == 0:
        return arr

    if n_bad > max_bad_fraction * arr.size:
        raise SignalError("%d of %d samples are NaN or infinite (%.1f%%), at most %.0f%% is allowed"
                          % (n_bad, arr.size, 100.0 * n_bad / arr.size, 100.0 * max_bad_fraction))

    longest = run = 0
    for flag in bad:
        run = run + 1 if flag else 0
        if run > longest:
            longest = run
    if longest / fs > max_bad_gap_seconds:
        raise SignalError("a gap of %d corrupt samples (%.2f s) cannot be interpolated, "
                          "at most %.1f s is allowed" % (longest, longest / fs, max_bad_gap_seconds))

    good = np.flatnonzero(~bad)
    arr = arr.copy()
    arr[bad] = np.interp(np.flatnonzero(bad), good, arr[good])
    return arr


def to_360hz(x, fs, target=TARGET_FS, aa_cutoff=AA_CUTOFF, aa_order=AA_ORDER):
    """Resample to 360 Hz, low-pass filtering first when the source is faster.

    Down-sampling 500..1000 Hz to 360 Hz would alias everything above 180 Hz into
    the band the model uses, so a Butterworth low-pass runs before the linear
    interpolation. Rates at (or below) 360 Hz are left alone.
    """
    fs = check_sample_rate(fs)
    x = np.asarray(x, dtype=float)
    if abs(fs - target) < FS_EPS:
        return x
    if fs > target:
        x = sosfilt(butterworth_lowpass_sos(fs, aa_cutoff, aa_order), x)
    return resample_linear(x, fs, target)


def detect_rpeaks(xf, sos_det, fs=FS):
    """Pan-Tompkins style R-peak detector. xf = signal already band-passed 0.5-40 Hz."""
    n = len(xf)
    det = filtfilt(sos_det, xf)

    # 5-point derivative, squaring, centered moving-window integration (about 150 ms)
    d = np.zeros(n)
    d[2:n - 2] = (2 * det[4:] + det[3:n - 1] - det[1:n - 3] - 2 * det[:n - 4]) * fs / 8
    sq = d * d
    half = int(0.15 * fs) // 2
    c = np.concatenate([[0.0], np.cumsum(sq)])
    idx = np.arange(n)
    lo = np.maximum(idx - half, 0)
    hi = np.minimum(idx + half + 1, n)
    mwi = (c[hi] - c[lo]) / (hi - lo)

    # candidates = local maxima of the integrated signal
    cand = [i for i in range(1, n - 1) if mwi[i] > mwi[i - 1] and mwi[i] >= mwi[i + 1]]

    refr = int(0.2 * fs)

    # Robust initial thresholds.  Taking 0.5 * max(mwi[:2 s]) means a single 50 mV
    # spike near the start raises the signal peak so far that the threshold never
    # comes back down and every real beat is missed.  The median of the maxima of
    # 2 s blocks over the first 8 s ignores such an outlier, and the noise peak is
    # a median too (robust to individual candidates).
    init_end = min(n, 8 * fs)
    block = 2 * fs
    block_max = [float(np.max(mwi[i:min(i + block, init_end)]))
                 for i in range(0, init_end, block)]
    block_max = [v for v in block_max if v > 0]
    spki = float(np.median(block_max)) if block_max else 0.0
    npki = float(np.median(mwi[:init_end])) if init_end > 0 else 0.0
    if npki > spki:
        npki = 0.5 * spki

    accepted = []     # [position, height]
    rejected = []     # [position, height]
    rj = 0            # forward pointer into `rejected`, keeps search-back O(N) overall
    for ci in cand:
        h = mwi[ci]
        thr = npki + 0.25 * (spki - npki)
        if h > thr:
            if accepted and ci - accepted[-1][0] < refr:
                if h > accepted[-1][1]:            # keep the larger one inside the refractory period
                    accepted[-1] = [ci, h]
                continue
            # search-back: a long gap means we probably missed a beat.
            # `lo_pos` and `hi_pos` only ever move forward, so a single pointer
            # walks the rejected list once instead of rescanning it per beat.
            if len(accepted) > 8:
                rr = np.mean(np.diff([a[0] for a in accepted[-9:]]))
                if ci - accepted[-1][0] > 1.66 * rr:
                    lo_pos = accepted[-1][0] + refr
                    hi_pos = ci - refr
                    while rj < len(rejected) and rejected[rj][0] < lo_pos:
                        rj += 1
                    best = None
                    j = rj
                    while j < len(rejected) and rejected[j][0] <= hi_pos:
                        if rejected[j][1] > 0.5 * thr and (best is None or rejected[j][1] > best[1]):
                            best = rejected[j]
                        j += 1
                    if best is not None:
                        accepted.append(best)
            accepted.append([ci, h])
            # Cap the jump: one noisy peak may not quadruple the signal estimate.
            spki = 0.125 * (min(h, 4.0 * spki) if spki > 0 else h) + 0.875 * spki
        else:
            rejected.append([ci, h])
            npki = 0.125 * h + 0.875 * npki

    # refine: position of the largest deflection of the filtered signal near each detection
    w = int(0.08 * fs)
    peaks = []
    for pos, _ in accepted:
        a, b = max(0, pos - w), min(n, pos + w + 1)
        peaks.append(a + int(np.argmax(np.abs(xf[a:b]))))

    # remove duplicates created by refinement
    out = []
    for p in sorted(peaks):
        if out and p - out[-1] < refr:
            if abs(xf[p]) > abs(xf[out[-1]]):
                out[-1] = p
            continue
        out.append(p)
    return np.array(out, dtype=int)

# ---------------------------------------------------------------------------
# Beat features, Random Forest evaluation and the full reference pipeline
# ---------------------------------------------------------------------------
PRE, POST = 90, 110      # samples before / after each R-peak
R = 90                   # position of the R-peak inside a beat window


def resample_linear(x, fs, target=FS):
    """Linear-interpolation resampling to 360 Hz (exact rate check, no rounding)."""
    fs = check_sample_rate(fs)
    x = np.asarray(x, dtype=float)
    if abs(fs - target) < FS_EPS:
        return x
    if x.size == 0:
        return x
    n_out = int(len(x) * target / fs)
    if n_out <= 0:
        return np.zeros(0, dtype=float)
    t = np.arange(n_out) * fs / target
    return np.interp(t, np.arange(len(x)), x)


def beat_features(beat, prev_rr, next_rr, med_rr):
    """57 features of one beat (200 samples) and its neighbouring R-R intervals (in samples)."""
    x = np.asarray(beat, dtype=float)
    x = x - np.median(x)

    peak = x.max()
    trough = x.min()
    p2p = peak - trough
    amp_r = x[R]
    t_peak = int(np.argmax(x)) - R        # first index on ties
    t_trough = int(np.argmin(x)) - R

    thr = 0.3 * np.abs(x).max()
    width = int(np.sum(np.abs(x[R - 40:R + 40]) > thr))

    energy = float(np.sum(x * x))
    area = float(np.sum(np.abs(x)))

    dev = x - x.mean()
    m2 = float(np.mean(dev ** 2))
    m3 = float(np.mean(dev ** 3))
    m4 = float(np.mean(dev ** 4))
    sd = m2 ** 0.5
    if m2 > 1e-12:
        sk = m3 / m2 ** 1.5
        ku = m4 / m2 ** 2 - 3.0
    else:
        sk = 0.0
        ku = 0.0

    shape = x[::5] / (p2p + 1e-8)         # 40 values

    rr_part = [prev_rr, next_rr, prev_rr / next_rr, prev_rr / med_rr, next_rr / med_rr]
    morph = [amp_r, peak, trough, p2p, t_peak, t_trough, width, energy, area, sd, sk, ku]
    return np.concatenate([rr_part, morph, shape])


def export_forest(model, decimals=6):
    """Turn a fitted sklearn RandomForestClassifier into plain lists (JSON friendly)."""
    assert list(model.classes_) == [0, 1, 2, 3]
    trees = []
    for est in model.estimators_:
        t = est.tree_
        value = t.value[:, 0, :]
        proba = value / value.sum(axis=1, keepdims=True)
        leaf = t.children_left == -1
        trees.append({
            "feature": [-1 if lf else int(f) for f, lf in zip(t.feature, leaf)],
            "threshold": [0.0 if lf else float(th) for th, lf in zip(t.threshold, leaf)],
            "left": [int(v) for v in t.children_left],
            "right": [int(v) for v in t.children_right],
            "value": [np.round(p, decimals).tolist() if lf else None
                      for p, lf in zip(proba, leaf)],
        })
    return {"n_classes": 4, "trees": trees}


def forest_predict_proba(forest, x):
    """Average of the leaf probabilities of all trees, like sklearn's predict_proba."""
    # sklearn casts features to float32 before comparing them with the (float64) thresholds
    xr = np.asarray(x, dtype=np.float32).astype(np.float64)
    if not np.all(np.isfinite(xr)):
        # NaN would compare False against every threshold and silently follow the
        # right branch of the tree, so refuse the input instead of guessing.
        raise ValueError("beat features must be finite: NaN or Inf would silently "
                         "turn into a right-branch decision in every tree")
    xr = xr.tolist()
    total = [0.0, 0.0, 0.0, 0.0]
    for t in forest["trees"]:
        left, right, feat, thr = t["left"], t["right"], t["feature"], t["threshold"]
        i = 0
        while left[i] != -1:
            i = left[i] if xr[feat[i]] <= thr[i] else right[i]
        v = t["value"][i]
        for c in range(4):
            total[c] += v[c]
    n = len(forest["trees"])
    return np.array([s / n for s in total])


def analyze_reference(sig, fs, cfg, forest):
    """Everything the phone has to do, using only the simple functions of this file."""
    sos_main = np.asarray(cfg["sos_main"], dtype=float)
    sos_det = np.asarray(cfg["sos_det"], dtype=float)

    sig = sanitize_signal(sig, fs)
    sig = to_360hz(sig, fs)
    sig_f = filtfilt(sos_main, sig)
    peaks = detect_rpeaks(sig_f, sos_det)

    beats, rr, used = [], [], []
    for k in range(1, len(peaks) - 1):
        p = int(peaks[k])
        if p - PRE < 0 or p + POST > len(sig_f):
            continue
        beats.append(sig_f[p - PRE:p + POST])
        rr.append((int(peaks[k] - peaks[k - 1]), int(peaks[k + 1] - peaks[k])))
        used.append(p)

    if len(beats) == 0:
        return {"signal": sig_f, "peaks": np.array([], dtype=int),
                "pred": np.array([], dtype=int), "proba": np.zeros((0, 4))}

    med = float(np.median([r[0] for r in rr]))
    w = np.asarray(cfg["decision_weights"], dtype=float)
    proba = np.array([forest_predict_proba(forest, beat_features(b, r[0], r[1], med))
                      for b, r in zip(beats, rr)])
    pred = (proba * w).argmax(1)
    return {"signal": sig_f, "peaks": np.array(used), "pred": pred, "proba": proba}