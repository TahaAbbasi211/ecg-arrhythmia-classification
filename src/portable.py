"""Portable signal processing (numpy only, simple loops) so the same logic can be ported to Dart.

Only the filter coefficients (SOS) are generated with scipy; every function here uses
plain numpy / python so that each step can be re-implemented 1:1 on a phone.
"""
import numpy as np

FS = 360


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
    init = mwi[:2 * fs]
    spki = 0.5 * init.max()
    npki = 0.5 * init.mean()

    accepted = []     # [position, height]
    rejected = []     # [position, height]
    for ci in cand:
        h = mwi[ci]
        thr = npki + 0.25 * (spki - npki)
        if h > thr:
            if accepted and ci - accepted[-1][0] < refr:
                if h > accepted[-1][1]:            # keep the larger one inside the refractory period
                    accepted[-1] = [ci, h]
                continue
            # search-back: a long gap means we probably missed a beat
            if len(accepted) > 8:
                rr = np.mean(np.diff([a[0] for a in accepted[-9:]]))
                if ci - accepted[-1][0] > 1.66 * rr:
                    lo_pos = accepted[-1][0] + refr
                    hi_pos = ci - refr
                    pool = [r for r in rejected if lo_pos <= r[0] <= hi_pos and r[1] > 0.5 * thr]
                    if pool:
                        best = max(pool, key=lambda r: r[1])
                        accepted.append(best)
            accepted.append([ci, h])
            spki = 0.125 * h + 0.875 * spki
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
    """Linear-interpolation resampling to 360 Hz."""
    x = np.asarray(x, dtype=float)
    if int(round(fs)) == target:
        return x
    n_out = int(len(x) * target / fs)
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
    xr = np.asarray(x, dtype=np.float32).astype(np.float64).tolist()
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

    sig = resample_linear(sig, fs)
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