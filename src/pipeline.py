import json
import os
from math import gcd

import numpy as np
from scipy.signal import butter, filtfilt, resample_poly

from src import portable
from src.features import build_features
from src.features_v3 import extract_recording_features_v3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_MODEL = os.path.join("export", "ecg_model_v3.json")

TARGET_FS = 360          # sampling rate the model was trained on
PRE, POST = 90, 110      # samples before / after each R-peak
CLASSES = ["N", "S", "V", "F"]

# F (fusion) beats are not predicted: 372 of 414 DS1 training F beats come from a
# single patient (208), and boosting F produced massive false alarms in CV.
# This is the fallback only; the shipped JSON model stores its own
# `decision_weights` ([1.0, 0.25, 0.5, 0.0]) and that value always wins.
DECISION_WEIGHTS = np.array([1.0, 0.25, 0.5, 0.0])

AAMI_MAP = {
    "N": "N", "L": "N", "R": "N", "e": "N", "j": "N",
    "A": "S", "a": "S", "J": "S", "S": "S",
    "V": "V", "E": "V",
    "F": "F",
    "/": "Q", "f": "Q", "Q": "Q",
}


def load_model(path=None):
    """Load the v3.1 JSON model bundle or a legacy joblib bundle.

    Defaults to `export/ecg_model_v3.json` as the single source of truth so
    inference has no runtime dependency on scikit-learn or joblib. Legacy
    `.joblib` paths (such as `models/ecg_rf_small.joblib`) are still supported.
    """
    if path is None:
        path = DEFAULT_MODEL
    if not os.path.isabs(path) and not os.path.exists(path):
        candidate = os.path.join(ROOT, path)
        if os.path.exists(candidate):
            path = candidate
    if str(path).lower().endswith(".json"):
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
        return {
            "kind": payload.get("kind", "hgb"),
            "schema_version": payload.get("schema_version", 3),
            "model": payload,
            "decision_weights": np.asarray(
                payload.get("decision_weights", DECISION_WEIGHTS),
                dtype=float,
            ),
            "feature_count": int(payload.get("feature_count", 84)),
            "classes": list(payload.get("classes", [0, 1, 2])),
            "path": path,
        }
    import joblib

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
    return {
        "signal": sig_f,
        "peaks": np.array([], dtype=int),
        "pred": np.array([], dtype=int),
        "proba": np.zeros((0, 4), dtype=np.float64),
        "scores": np.zeros((0, 4), dtype=np.float64),
        "fs": TARGET_FS,
    }


def _classify(sig_f, peaks, bundle):
    """Cut a beat around every R-peak, build features and predict its class."""
    peaks = np.asarray(peaks)
    if len(peaks) < 3:
        return _empty(sig_f)

    X, rr, used = [], [], []
    for k in range(1, len(peaks) - 1):
        p = int(peaks[k])
        if p - PRE < 0 or p + POST > len(sig_f):
            continue
        X.append(sig_f[p - PRE:p + POST])
        rr.append([int(peaks[k] - peaks[k - 1]), int(peaks[k + 1] - peaks[k])])
        used.append(p)

    if len(X) == 0:
        return _empty(sig_f)

    X = np.asarray(X, dtype=np.float64)
    rr = np.asarray(rr, dtype=np.float64)
    model_obj = bundle.get("model", bundle) if isinstance(bundle, dict) else bundle

    if isinstance(model_obj, dict) and model_obj.get("kind") == "hgb":
        F = extract_recording_features_v3(X, rr, fs=TARGET_FS)
        proba = np.asarray([portable.hgb_predict_proba(model_obj, row) for row in F], dtype=np.float64)
    elif isinstance(model_obj, dict) and "trees" in model_obj:
        F = build_features(X, rr, np.zeros(len(X), dtype=int))
        proba = np.asarray([portable.forest_predict_proba(model_obj, row) for row in F], dtype=np.float64)
    else:
        n_in = getattr(model_obj, "n_features_in_", 57)
        if n_in == 84:
            F = extract_recording_features_v3(X, rr, fs=TARGET_FS)
        else:
            F = build_features(X, rr, np.zeros(len(X), dtype=int))
        proba = np.zeros((len(X), 4), dtype=np.float64)
        proba[:, model_obj.classes_] = model_obj.predict_proba(F)

    default_weights = (
        model_obj.get("decision_weights", DECISION_WEIGHTS)
        if isinstance(model_obj, dict)
        else DECISION_WEIGHTS
    )
    if isinstance(bundle, dict):
        weights = bundle.get("decision_weights", bundle.get("weights", default_weights))
    else:
        weights = default_weights
    weights = np.asarray(weights, dtype=np.float64)
    scores = portable.effective_scores(proba, weights)
    pred = (proba * weights).argmax(1)

    return {
        "signal": sig_f,
        "peaks": np.array(used, dtype=int),
        "pred": pred,
        "proba": proba,
        "scores": scores,
        "fs": TARGET_FS,
    }


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