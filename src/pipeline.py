import numpy as np
import joblib
from math import gcd
from scipy.signal import butter, filtfilt, resample_poly
from wfdb import processing

from src import portable
from src.features import build_features

TARGET_FS = 360          # sampling rate the model was trained on
PRE, POST = 90, 110      # samples before / after each R-peak
CLASSES = ["N", "S", "V", "F"]

# F (fusion) beats are not predicted: only 414 training beats from a few patients,
# and boosting F produced thousands of false alarms on test patients.
DECISION_WEIGHTS = np.array([1.0, 4.0, 1.0, 0.0])

AAMI_MAP = {
    "N": "N", "L": "N", "R": "N", "e": "N", "j": "N",
    "A": "S", "a": "S", "J": "S", "S": "S",
    "V": "V", "E": "V",
    "F": "F",
    "/": "Q", "f": "Q", "Q": "Q",
}


def load_model(path="models/ecg_rf.joblib"):
    return joblib.load(path)


def bandpass(sig, fs, low=0.5, high=40, order=3):
    b, a = butter(order, [low, high], btype="band", fs=fs)
    return filtfilt(b, a, sig)


def to_360hz(sig, fs):
    fs = int(round(fs))
    if fs == TARGET_FS:
        return sig
    g = gcd(fs, TARGET_FS)
    return resample_poly(sig, TARGET_FS // g, fs // g)


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
    weights = bundle.get("decision_weights", DECISION_WEIGHTS)
    pred = (proba * weights).argmax(1)

    return {"signal": sig_f, "peaks": np.array(used), "pred": pred,
            "proba": proba, "fs": TARGET_FS}


def analyze(sig, fs, bundle):
    """Original pipeline: scipy filter + XQRS R-peak detector (wfdb)."""
    sig = to_360hz(np.asarray(sig, dtype=float), fs)
    sig_f = bandpass(sig, TARGET_FS)
    peaks = np.asarray(processing.xqrs_detect(sig=sig, fs=TARGET_FS, verbose=False))
    return _classify(sig_f, peaks, bundle)


_SOS = None


def analyze_portable(sig, fs, bundle):
    """Portable pipeline: filter and R-peak detector use only simple numpy code (src/portable.py)."""
    global _SOS
    if _SOS is None:
        _SOS = portable.make_sos()
    sos_main, sos_det = _SOS

    sig = to_360hz(np.asarray(sig, dtype=float), fs)
    sig_f = portable.filtfilt(sos_main, sig)
    peaks = portable.detect_rpeaks(sig_f, sos_det)
    return _classify(sig_f, peaks, bundle)