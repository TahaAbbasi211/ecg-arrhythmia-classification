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