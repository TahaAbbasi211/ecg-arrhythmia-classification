"""Reproducible exporter for the frozen Phase 1 winning v3.1.0 HGB model.

Trains the exact frozen HistGradientBoostingClassifier configuration on the
22 DS1 patients (classes N, S, V only) using the 84 scale-invariant v3 features,
exports the compact float64 JSON single source of truth (`export/ecg_model_v3.json`),
updates `export/ecg_config.json`, verifies < 1e-5 probability parity and 0 label
flips against scikit-learn on >= 5,000 DS2 beats, and benchmarks pure-Python
loop inference speed (`loop_ms_per_1k`).

Usage:
    D:\\ANACONDA\\python.exe scripts/export_v3_model.py
"""

import hashlib
import json
import os
import sys
import time

import numpy as np
from scipy.signal import butter, filtfilt
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.utils.class_weight import compute_sample_weight
import wfdb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from src import features_v3, portable  # noqa: E402

DATA_DIR = os.path.join(ROOT, "data", "mitdb")
EXPORT_DIR = os.path.join(ROOT, "export")
MODEL_OUT = os.path.join(EXPORT_DIR, "ecg_model_v3.json")
CONFIG_PATH = os.path.join(EXPORT_DIR, "ecg_config.json")

DS1 = [101, 106, 108, 109, 112, 114, 115, 116, 118, 119, 122, 124,
       201, 203, 205, 207, 208, 209, 215, 220, 223, 230]
DS2 = [100, 103, 105, 111, 113, 117, 121, 123, 200, 202, 210, 212,
       213, 214, 219, 221, 222, 228, 231, 232, 233, 234]

CLASSES = ["N", "S", "V", "F"]
AAMI_ALL = {
    "N": "N", "L": "N", "R": "N", "e": "N", "j": "N",
    "A": "S", "a": "S", "J": "S", "S": "S",
    "V": "V", "E": "V",
    "F": "F",
    "/": "Q", "f": "Q", "Q": "Q",
}
FS = 360
PRE, POST = 90, 110
SEED = 42
DECISION_WEIGHTS = [1.0, 0.25, 0.5, 0.0]


def _load_split(records):
    """Load annotation-aligned beats, labels (no Q), R-R intervals, and groups."""
    b, a = butter(3, [0.5, 40.0], btype="band", fs=FS)
    X_parts, y_parts, rr_parts, g_parts = [], [], [], []
    for rec_id in records:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec_id)))
        ann = wfdb.rdann(os.path.join(DATA_DIR, str(rec_id)), "atr")
        ch = record.sig_name.index("MLII")
        sig = filtfilt(b, a, record.p_signal[:, ch])

        keep = [i for i, sym in enumerate(ann.symbol) if sym in AAMI_ALL]
        samples = ann.sample[keep]
        labels = [AAMI_ALL[ann.symbol[i]] for i in keep]

        X_rec, y_rec, rr_rec = [], [], []
        for k in range(1, len(samples) - 1):
            p = int(samples[k])
            if p - PRE < 0 or p + POST > len(sig):
                continue
            if labels[k] == "Q":
                continue
            X_rec.append(sig[p - PRE:p + POST])
            y_rec.append(CLASSES.index(labels[k]))
            rr_rec.append([int(samples[k] - samples[k - 1]), int(samples[k + 1] - samples[k])])

        X_parts.append(np.asarray(X_rec, dtype=np.float64))
        y_parts.append(np.asarray(y_rec, dtype=np.int64))
        rr_parts.append(np.asarray(rr_rec, dtype=np.int64))
        g_parts.append(np.full(len(y_rec), int(rec_id), dtype=np.int64))

    return (
        np.concatenate(X_parts),
        np.concatenate(y_parts),
        np.concatenate(rr_parts),
        np.concatenate(g_parts),
    )


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    print("Loading MIT-BIH DS1 and DS2...")
    X_ds1, y_ds1, rr_ds1, g_ds1 = _load_split(DS1)
    X_ds2, y_ds2, rr_ds2, g_ds2 = _load_split(DS2)
    assert len(y_ds1) == 50969, f"unexpected DS1 beat count: {len(y_ds1)}"
    assert len(y_ds2) == 49661, f"unexpected DS2 beat count: {len(y_ds2)}"

    print("Extracting 84 v3 features...")
    F_ds1 = features_v3.build_features_v3(X_ds1, rr_ds1, g_ds1, fs=FS)
    F_ds2 = features_v3.build_features_v3(X_ds2, rr_ds2, g_ds2, fs=FS)

    # Fit frozen Phase 1 winner strictly on DS1 classes N, S, V (drop F from fit).
    mask = y_ds1 != 3
    X_fit, y_fit = F_ds1[mask], y_ds1[mask]
    sw = compute_sample_weight("balanced", y_fit)

    model = HistGradientBoostingClassifier(
        max_iter=100,
        max_leaf_nodes=15,
        learning_rate=0.08,
        min_samples_leaf=30,
        l2_regularization=1.0,
        random_state=SEED,
    )
    print("Fitting HistGradientBoostingClassifier on DS1 (N, S, V)...")
    model.fit(X_fit, y_fit, sample_weight=sw)
    assert list(model.classes_) == [0, 1, 2]

    payload = portable.export_hgb(model, weights=DECISION_WEIGHTS)
    with open(MODEL_OUT, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))

    with open(CONFIG_PATH, encoding="utf-8") as handle:
        cfg = json.load(handle)

    updated_cfg = {
        "schema_version": 3,
        "model_file": "ecg_model_v3.json",
        "feature_count": len(features_v3.FEATURE_NAMES),
        "fs": cfg["fs"],
        "pre": cfg["pre"],
        "post": cfg["post"],
        "classes": cfg["classes"],
        "decision_weights": DECISION_WEIGHTS,
        "sos_main": cfg["sos_main"],
        "sos_det": cfg["sos_det"],
    }
    with open(CONFIG_PATH, "w", encoding="utf-8") as handle:
        json.dump(updated_cfg, handle, indent=1)

    with open(MODEL_OUT, encoding="utf-8") as handle:
        reloaded = json.load(handle)

    # Parity verification on >= 5,000 DS2 beats spanning all 22 DS2 patients.
    probe = F_ds2[::5]
    assert len(probe) >= 5000, f"probe too small: {len(probe)}"
    sk_proba = np.zeros((len(probe), 4), dtype=np.float64)
    sk_proba[:, model.classes_] = model.predict_proba(probe)
    loop_proba = np.asarray([portable.hgb_predict_proba(reloaded, row) for row in probe], dtype=np.float64)

    w = np.asarray(DECISION_WEIGHTS, dtype=np.float64)
    sk_pred = (sk_proba * w).argmax(1)
    loop_pred = (loop_proba * w).argmax(1)
    max_diff = float(np.max(np.abs(sk_proba - loop_proba)))
    label_flips = int(np.sum(sk_pred != loop_pred))

    assert max_diff < 1e-5, f"parity diff too large: {max_diff}"
    assert label_flips == 0, f"unexpected label flips: {label_flips}"

    # Measure true pure-Python loop speed (ms per 1,000 beats).
    speed_probe = F_ds2[:1000]
    _ = [portable.hgb_predict_proba(reloaded, row) for row in speed_probe[:100]]
    runs = []
    for _ in range(3):
        t0 = time.perf_counter()
        _ = [portable.hgb_predict_proba(reloaded, row) for row in speed_probe]
        runs.append((time.perf_counter() - t0) * (1_000_000.0 / len(speed_probe)))
    loop_ms_per_1k = float(np.mean(runs))

    model_bytes = os.path.getsize(MODEL_OUT)
    print(f"Exported {MODEL_OUT}: {model_bytes} bytes ({model_bytes / 1000:.1f} KB), sha256={_sha256(MODEL_OUT)}")
    print(f"Updated  {CONFIG_PATH}: sha256={_sha256(CONFIG_PATH)}")
    print(f"Parity check on {len(probe)} DS2 beats: max_abs_diff={max_diff:.3e}, label_flips={label_flips}")
    print(f"Pure-Python loop speed (mean of 3x1000 DS2 beats): {loop_ms_per_1k:.2f} ms / 1k beats")


if __name__ == "__main__":
    main()
