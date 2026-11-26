import os
from math import gcd

import joblib
import numpy as np
from scipy.signal import butter, filtfilt, resample_poly

from src import portable
from src.features import build_features

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_MODEL = os.path.join("models", "ecg_rf_small.joblib")

TARGET_FS = 360          # sampling rate the model was trained on
PRE, POST = 90, 110      # samples before / after each R-peak
CLASSES = ["N", "S", "V", "F"]

# F (fusion) beats are not predicted: only 414 training beats from a few patients,
# and boosting F produced thousands of false alarms on test patients.
# This is the fallback only: models/ecg_rf_small.joblib stores its own
# `decision_weights` ([1, 2, 1, 0]) and that value always wins.
DECISION_WEIGHTS = np.array([1.0, 2.0, 1.0, 0.0])

AAMI_MAP = {
    "N": "N", "L": "N", "R": "N", "e": "N", "j": "N",
    "A": "S", "a": "S", "J": "S", "S": "S",
    "V": "V", "E": "V",
    "F": "F",
    "/": "Q", "f": "Q", "Q": "Q",
}


def load_model(path=None):
    """Load a joblib bundle.

    Defaults to the small 50-tree forest that v2.1 ships (`models/ecg_rf_small.joblib`).
    A relative path is also looked up next to the repository root, so the notebooks
    and `pytest` behave the same no matter which directory they are started from.
    """
    if path is None:
        path = DEFAULT_MODEL
    if not os.path.isabs(path) and not os.path.exists(path):
        candidate = os.path.join(ROOT, path)
        if os.path.exists(candidate):
            path = candidate
    return joblib.load(path)


def bandpass(sig, fs, low=0.5, high=40, order=3):
    b, a = butter(order, [low, high], btype="band", fs=fs)
    return filtfilt(b, a, sig)


def to_360hz(sig, fs):
    """Polyphase resampling with scipy (the non-portable reference path only)."""
    rate = portable.check_sample_rate(fs)
    if abs(rate - TARGET_FS) < 1e-6:
        return sig
    rate = int(round(rate))
    g = gcd(rate, TARGET_FS)
    return resample_poly(sig, TARGET_FS // g, rate // g)


def _empty(sig_f):
    return {"signal": sig_f, "peaks": np.array([], dtype=int),
            "pred": np.array([], dtype=int), "proba": np.zeros((0, 4)),
            "fs": TARGET_FS}


def _classify(sig_f, peaks, bundle):
    """Cut a beat around every R-peak, build features and predict its class."""
    peaks = np.asarray(peaks)
    if len(peaks) < 3:
        return _empty(sig_f)

    X, rr, used = [], [], []
    for k in range(1, len(peaks) - 1):
        p = peaks[k]
        if p - PRE < 0 or p + POST > len(sig_f):
            continue
        X.append(sig_f[p - PRE:p + POST])
        rr.append([peaks[k] - peaks[k - 1], peaks[k + 1] - peaks[k]])
        used.append(p)

    if len(X) == 0:
        return _empty(sig_f)

    X, rr = np.array(X), np.array(rr)
    F = build_features(X, rr, np.zeros(len(X), dtype=int))

    model = bundle["model"]
    proba = np.zeros((len(X), 4))
    proba[:, model.classes_] = model.predict_proba(F)
    # The exported model is pickled in different places under both key names.
    weights = bundle.get("decision_weights", bundle.get("weights", DECISION_WEIGHTS))
    weights = np.asarray(weights, dtype=float)
    pred = (proba * weights).argmax(1)

    return {"signal": sig_f, "peaks": np.array(used), "pred": pred,
            "proba": proba, "fs": TARGET_FS}


def analyze(sig, fs, bundle):
    """Original pipeline: scipy filter + XQRS R-peak detector (wfdb).

    `wfdb` is imported here rather than at module level: it is a development/notebook
    dependency, and `analyze_portable()` (used by Streamlit and mirrored in Dart) has
    to work on a machine that never installed it.
    """
    from wfdb import processing

    rate = portable.check_sample_rate(fs)
    x = portable.sanitize_signal(sig, rate)
    x = to_360hz(x, rate)
    sig_f = bandpass(x, TARGET_FS)
    peaks = np.asarray(processing.xqrs_detect(sig=x, fs=TARGET_FS, verbose=False))
    return _classify(sig_f, peaks, bundle)


_SOS = None


def analyze_portable(sig, fs, bundle):
    """Portable pipeline: filter and R-peak detector use only simple numpy code (src/portable.py).

    Resampling goes through `portable.to_360hz` (linear interpolation + anti-aliasing
    low-pass above 360 Hz) instead of scipy's `resample_poly`, so Streamlit and the
    Android app produce the same numbers for 180, 250, 500 or 1000 Hz input.
    """
    global _SOS
    if _SOS is None:
        _SOS = portable.make_sos()
    sos_main, sos_det = _SOS

    rate = portable.check_sample_rate(fs)
    sig = portable.sanitize_signal(sig, rate)
    sig = portable.to_360hz(sig, rate)
    sig_f = portable.filtfilt(sos_main, sig)
    peaks = portable.detect_rpeaks(sig_f, sos_det)
    return _classify(sig_f, peaks, bundle)