import numpy as np

R = 90  # R-peak position inside each 200-sample beat


def rr_features(rr, g):
    prev_rr = rr[:, 0].astype(float)
    next_rr = rr[:, 1].astype(float)

    # median R-R interval of each patient
    med_rr = np.zeros_like(prev_rr)
    for rec in np.unique(g):
        m = g == rec
        med_rr[m] = np.median(prev_rr[m])

    return np.column_stack([
        prev_rr, next_rr,
        prev_rr / next_rr,
        prev_rr / med_rr,
        next_rr / med_rr,
    ])


def morph_features(X):
    X = X - np.median(X, axis=1, keepdims=True)

    peak = X.max(axis=1)
    trough = X.min(axis=1)
    p2p = peak - trough
    amp_r = X[:, R]
    t_peak = X.argmax(axis=1) - R
    t_trough = X.argmin(axis=1) - R

    thr = 0.3 * np.abs(X).max(axis=1, keepdims=True)
    width = (np.abs(X[:, R - 40:R + 40]) > thr).sum(axis=1)

    energy = (X ** 2).sum(axis=1)
    area = np.abs(X).sum(axis=1)

    # Population (biased) moments, computed here instead of scipy.stats so a flat
    # beat gives 0/0 where scipy returns NaN.  `src/portable.py` returns 0 there,
    # and the two implementations must agree feature for feature.
    dev = X - X.mean(axis=1, keepdims=True)
    m2 = (dev ** 2).mean(axis=1)
    m3 = (dev ** 3).mean(axis=1)
    m4 = (dev ** 4).mean(axis=1)
    sd = np.sqrt(m2)
    flat = m2 <= 1e-12
    safe = np.where(flat, 1.0, m2)
    sk = np.where(flat, 0.0, m3 / safe ** 1.5)
    ku = np.where(flat, 0.0, m4 / safe ** 2 - 3.0)

    shape = X[:, ::5] / (p2p[:, None] + 1e-8)

    return np.column_stack([amp_r, peak, trough, p2p, t_peak, t_trough,
                            width, energy, area, sd, sk, ku, shape])


def build_features(X, rr, g):
    return np.hstack([rr_features(rr, g), morph_features(X)])

def context_rr_features(rr, g, k=10):
    prev_rr = rr[:, 0].astype(float)
    next_rr = rr[:, 1].astype(float)
    n = len(prev_rr)

    local = np.zeros(n)   # average of the previous k R-R intervals
    prev2 = np.zeros(n)   # R-R interval before the previous beat
    next2 = np.zeros(n)   # R-R interval after the next beat

    for rec in np.unique(g):
        idx = np.where(g == rec)[0]
        p = prev_rr[idx]
        nx = next_rr[idx]
        cs = np.concatenate([[0], np.cumsum(p)])

        for j in range(len(p)):
            lo = max(0, j - k)
            local[idx[j]] = p[j] if j == lo else (cs[j] - cs[lo]) / (j - lo)

        prev2[idx[1:]] = p[:-1]
        prev2[idx[0]] = p[0]
        next2[idx[:-1]] = nx[1:]
        next2[idx[-1]] = nx[-1]

    return np.column_stack([
        local,
        prev_rr / local,
        next_rr / local,
        (prev_rr + next_rr) / local,
        prev2 / local,
        next2 / local,
    ])


def build_features_v2(X, rr, g):
    return np.hstack([rr_features(rr, g), context_rr_features(rr, g), morph_features(X)])