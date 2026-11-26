"""Phase 1 v3.0 research, feature ablation, leak-free model selection, and benchmarks.

Strict anti-leakage protocol:
1. Lock the de Chazal inter-patient split (DS1: 22 train patients, DS2: 22 test
   patients, excluding paced records 102, 104, 107, 217 and dropping class Q).
2. Perform ALL decisions (feature ablation, handling class F, model family,
   hyperparameters, decision weights, short-clip stability) exclusively inside
   5-fold patient-grouped CV (StratifiedGroupKFold) on DS1.
3. Freeze a single winning model + OOF weights from DS1 CV, then evaluate DS2
   EXACTLY ONCE (annotation-aligned and end-to-end from raw signal).

Usage:
    D:\\ANACONDA\\python.exe scripts/train_v3.py
    D:\\ANACONDA\\python.exe scripts/train_v3.py --skip-svdb
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import warnings

os.environ.setdefault("LOKY_MAX_CPU_COUNT", str(os.cpu_count() or 4))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)
warnings.filterwarnings("ignore", message="Could not find the number of physical cores")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import joblib  # noqa: E402
import numpy as np  # noqa: E402
from scipy.signal import butter, filtfilt as scipy_filtfilt, sosfilt as scipy_sosfilt  # noqa: E402
from sklearn.ensemble import (  # noqa: E402
    ExtraTreesClassifier,
    GradientBoostingClassifier,
    HistGradientBoostingClassifier,
    RandomForestClassifier,
)
from sklearn.metrics import (  # noqa: E402
    accuracy_score,
    classification_report,
    f1_score,
    precision_recall_fscore_support,
)
from sklearn.model_selection import StratifiedGroupKFold  # noqa: E402
from sklearn.neural_network import MLPClassifier  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402
from sklearn.utils.class_weight import compute_sample_weight  # noqa: E402
import wfdb  # noqa: E402

from app.signal_io import read_signal_frame  # noqa: E402
from src import features as features_v2  # noqa: E402
from src import features_v3, portable  # noqa: E402

DATA_DIR = os.path.join(ROOT, "data", "mitdb")
PACED_RECORDS = (102, 104, 107, 217)
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


def bandpass_scipy(sig, fs=FS, low=0.5, high=40.0, order=3):
    """Same preprocessing band-pass filter used by notebook 02_preprocessing."""
    b, a = butter(order, [low, high], btype="band", fs=fs)
    return scipy_filtfilt(b, a, sig)


def fast_filtfilt_sos(sos, x, padlen=720):
    """Fast scipy-accelerated equivalent of `portable.filtfilt` (verified <1e-12 parity)."""
    arr = np.asarray(x, dtype=float)
    if arr.size == 0:
        return np.array([], dtype=float)
    n = min(padlen, len(arr) - 1)
    left = 2.0 * arr[0] - arr[n:0:-1]
    right = 2.0 * arr[-1] - arr[-2:-(n + 2):-1]
    y = np.concatenate([left, arr, right])
    y = scipy_sosfilt(sos, y)
    y = scipy_sosfilt(sos, y[::-1])[::-1]
    return y[n:len(y) - n]


def load_mitdb_split(records):
    """Load annotation-aligned beats, labels (without Q), R-R intervals, groups, and sample indices."""
    X_parts, y_parts, rr_parts, g_parts, s_parts = [], [], [], [], []
    for rec_id in records:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec_id)))
        ann = wfdb.rdann(os.path.join(DATA_DIR, str(rec_id)), "atr")
        ch = record.sig_name.index("MLII")
        sig = bandpass_scipy(record.p_signal[:, ch], record.fs)

        keep = [i for i, sym in enumerate(ann.symbol) if sym in AAMI_ALL]
        samples = ann.sample[keep]
        labels = [AAMI_ALL[ann.symbol[i]] for i in keep]

        X_rec, y_rec, rr_rec, s_rec = [], [], [], []
        for k in range(1, len(samples) - 1):
            p = int(samples[k])
            if p - PRE < 0 or p + POST > len(sig):
                continue
            if labels[k] == "Q":
                continue
            X_rec.append(sig[p - PRE:p + POST])
            y_rec.append(CLASSES.index(labels[k]))
            rr_rec.append([int(samples[k] - samples[k - 1]), int(samples[k + 1] - samples[k])])
            s_rec.append(p)

        X_parts.append(np.asarray(X_rec, dtype=np.float64))
        y_parts.append(np.asarray(y_rec, dtype=np.int64))
        rr_parts.append(np.asarray(rr_rec, dtype=np.int64))
        g_parts.append(np.full(len(y_rec), int(rec_id), dtype=np.int64))
        s_parts.append(np.asarray(s_rec, dtype=np.int64))

    return (
        np.concatenate(X_parts),
        np.concatenate(y_parts),
        np.concatenate(rr_parts),
        np.concatenate(g_parts),
        np.concatenate(s_parts),
    )


def verify_split_integrity(X_train, y_train, rr_train, g_train, X_test, y_test, rr_test, g_test):
    """Assert exact de Chazal split invariants and parity with data/processed/beats.npz."""
    assert len(DS1) == 22 and len(DS2) == 22
    assert set(DS1).isdisjoint(set(DS2))
    assert set(DS1).isdisjoint(set(PACED_RECORDS))
    assert set(DS2).isdisjoint(set(PACED_RECORDS))
    assert len(y_train) == 50969
    assert len(y_test) == 49661

    npz_path = os.path.join(ROOT, "data", "processed", "beats.npz")
    if os.path.exists(npz_path):
        d = np.load(npz_path)
        for split, X_s, y_s, rr_s, g_s in [
            ("train", X_train, y_train, rr_train, g_train),
            ("test", X_test, y_test, rr_test, g_test),
        ]:
            m = d[f"y_{split}"] != 4
            assert np.array_equal(y_s, d[f"y_{split}"][m])
            assert np.array_equal(rr_s, d[f"rr_{split}"][m])
            assert np.array_equal(g_s, d[f"g_{split}"][m])
            assert np.allclose(X_s, d[f"X_{split}"][m], atol=1e-10, rtol=0)


# ---------------------------------------------------------------------------
# Feature matrix helpers
# ---------------------------------------------------------------------------

def build_ablation_matrices(X, rr, g):
    """Construct ablation feature matrices for a single data split (no cross-split leakage)."""
    F_v21 = features_v2.build_features(X, rr, g)
    F_v3 = features_v3.build_features_v3(X, rr, g)
    rr_v21 = F_v21[:, :5]
    rhythm_v3 = F_v3[:, features_v3.FEATURE_GROUPS["rhythm"]]
    morph_v3 = F_v3[:, features_v3.FEATURE_GROUPS["morph"]]
    tpl_v3 = F_v3[:, features_v3.FEATURE_GROUPS["template"]]
    pt_v3 = F_v3[:, features_v3.FEATURE_GROUPS["pt_wave"]]

    return {
        "v2.1_baseline_57": F_v21,
        "v2.1_rr_plus_rec_scale_morph_57": np.hstack([rr_v21, morph_v3]),
        "v3_rec_scale_plus_local_rr_66": np.hstack([rhythm_v3, morph_v3]),
        "v3_rec_scale_plus_template_pt_v21rr_75": np.hstack([rr_v21, morph_v3, tpl_v3, pt_v3]),
        "v3_full_84": F_v3,
    }


def make_clip_groups(g, samples, clip_seconds):
    """Assign each beat to an independent chronological clip ID `rec * 10000 + bucket`."""
    clip_len = int(clip_seconds * FS)
    buckets = samples // clip_len
    return g * 10000 + buckets


# ---------------------------------------------------------------------------
# Metrics & OOF decision weight tuning
# ---------------------------------------------------------------------------

def compute_metrics(y_true, y_pred):
    """Compute per-class precision/recall/F1, NSV macro F1, 4-class macro F1, and accuracy."""
    prec, rec, f1, sup = precision_recall_fscore_support(
        y_true, y_pred, labels=[0, 1, 2, 3], zero_division=0
    )
    macro_nsv = float(f1_score(y_true, y_pred, labels=[0, 1, 2], average="macro", zero_division=0))
    macro_all = float(f1_score(y_true, y_pred, labels=[0, 1, 2, 3], average="macro", zero_division=0))
    acc = float(accuracy_score(y_true, y_pred))
    return {
        "accuracy": acc,
        "macro_f1_nsv": macro_nsv,
        "macro_f1_4": macro_all,
        "per_class": {
            CLASSES[c]: {
                "precision": float(prec[c]),
                "recall": float(rec[c]),
                "f1": float(f1[c]),
                "support": int(sup[c]),
            }
            for c in range(4)
        },
    }


def _fast_f1_per_class(y, pred):
    """Fast exact 4-class F1 vector using np.bincount confusion matrix."""
    cm = np.bincount(y * 4 + pred, minlength=16).reshape(4, 4)
    tp = np.diag(cm).astype(np.float64)
    fp = cm.sum(axis=0) - tp
    fn = cm.sum(axis=1) - tp
    denom = 2.0 * tp + fp + fn
    return np.where(denom > 0.0, (2.0 * tp) / np.where(denom > 0.0, denom, 1.0), 0.0)


def tune_weights_nsv(proba, y, min_n_f1=0.94):
    """Tune [1.0, w_S, w_V, 0.0] on DS1 OOF probabilities to maximize Macro F1 (N, S, V)."""
    ws_grid = (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0)
    wv_grid = (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0)

    best_guarded, w_guarded = -1.0, None
    best_any, w_any = -1.0, np.array([1.0, 1.0, 1.0, 0.0])

    p0 = proba[:, 0]
    p1 = proba[:, 1]
    p2 = proba[:, 2]

    for ws in ws_grid:
        s1 = p1 * ws
        for wv in wv_grid:
            s2 = p2 * wv
            pred = np.where(s1 > p0, np.where(s2 > s1, 2, 1), np.where(s2 > p0, 2, 0))
            f1s = _fast_f1_per_class(y, pred)
            macro = float((f1s[0] + f1s[1] + f1s[2]) / 3.0)
            if macro > best_any:
                best_any = macro
                w_any = np.array([1.0, float(ws), float(wv), 0.0])
            if float(f1s[0]) >= min_n_f1 and macro > best_guarded:
                best_guarded = macro
                w_guarded = np.array([1.0, float(ws), float(wv), 0.0])

    if w_guarded is not None:
        return w_guarded, best_guarded
    return w_any, best_any


def tune_weights_with_f(proba, y):
    """Tune all 4 weights [1, w_S, w_V, w_F] on DS1 OOF to test class F feasibility."""
    grid = (0.0, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0)
    best_macro4, best_w4 = -1.0, np.array([1.0, 1.0, 1.0, 0.0])
    for ws in (0.5, 1.0, 2.0, 4.0, 8.0):
        for wv in (0.5, 1.0, 2.0, 4.0):
            for wf in grid:
                w = np.array([1.0, ws, wv, wf], dtype=float)
                pred = (proba * w).argmax(1)
                f1s = _fast_f1_per_class(y, pred)
                m4 = float(f1s.mean())
                if m4 > best_macro4:
                    best_macro4 = m4
                    best_w4 = w
    return best_w4, best_macro4


def evaluate_oof_folds(oof, y, g, folds):
    """Tune OOF weights, compute global OOF metrics, 5-fold mean/std, and nested fold-out score."""
    w, _ = tune_weights_nsv(oof, y)
    pred_global = (oof * w).argmax(1)
    global_metrics = compute_metrics(y, pred_global)

    fold_macros = []
    nested_preds = np.zeros_like(y)
    for _, va in folds:
        m_fold = f1_score(y[va], pred_global[va], labels=[0, 1, 2], average="macro", zero_division=0)
        fold_macros.append(float(m_fold))

        # Nested fold-out weight check (weights tuned only on the other 4 folds).
        tr_mask = np.ones(len(y), dtype=bool)
        tr_mask[va] = False
        w_nested, _ = tune_weights_nsv(oof[tr_mask], y[tr_mask])
        nested_preds[va] = (oof[va] * w_nested).argmax(1)

    nested_metrics = compute_metrics(y, nested_preds)
    return {
        "weights": w.tolist(),
        "oof_metrics": global_metrics,
        "fold_macro_mean": float(np.mean(fold_macros)),
        "fold_macro_std": float(np.std(fold_macros)),
        "nested_macro_f1_nsv": nested_metrics["macro_f1_nsv"],
        "nested_s_f1": nested_metrics["per_class"]["S"]["f1"],
        "nested_v_f1": nested_metrics["per_class"]["V"]["f1"],
    }


# ---------------------------------------------------------------------------
# Candidate model builders + fold-safe training + portable JSON export/inference
# ---------------------------------------------------------------------------

class ScaledMLP:
    """Wrapper binding a fold-local StandardScaler, optional minority oversampling, and MLP."""

    def __init__(self, hidden_layer_sizes=(64, 32), alpha=1e-2, max_iter=50,
                 oversample_ratio=0.0, random_state=SEED):
        self.hidden_layer_sizes = hidden_layer_sizes
        self.alpha = alpha
        self.max_iter = max_iter
        self.oversample_ratio = oversample_ratio
        self.random_state = random_state
        self.scaler = StandardScaler()
        self.mlp = MLPClassifier(
            hidden_layer_sizes=hidden_layer_sizes,
            activation="relu",
            alpha=alpha,
            batch_size=256,
            learning_rate_init=1e-3,
            max_iter=max_iter,
            early_stopping=True,
            validation_fraction=0.1,
            n_iter_no_change=6,
            random_state=random_state,
        )
        self.classes_ = None

    def fit(self, X, y, sample_weight=None):
        Xs = self.scaler.fit_transform(X)
        yf = y
        if self.oversample_ratio > 0.0:
            rng = np.random.RandomState(self.random_state)
            n_norm = int((y == 0).sum())
            target_min = max(1, int(round(self.oversample_ratio * n_norm)))
            extra_x, extra_y = [Xs], [y]
            for c in (1, 2, 3):
                idx_c = np.flatnonzero(y == c)
                if 0 < len(idx_c) < target_min:
                    chosen = rng.choice(idx_c, size=target_min - len(idx_c), replace=True)
                    extra_x.append(Xs[chosen])
                    extra_y.append(y[chosen])
            Xs = np.vstack(extra_x)
            yf = np.concatenate(extra_y)
            perm = rng.permutation(len(yf))
            Xs, yf = Xs[perm], yf[perm]

        self.mlp.fit(Xs, yf)
        self.classes_ = self.mlp.classes_
        return self

    def predict_proba(self, X):
        Xs = self.scaler.transform(X)
        return self.mlp.predict_proba(Xs)


def fit_candidate(spec, X_tr, y_tr):
    """Instantiate and fit a candidate model cleanly inside a fold or on full DS1."""
    kind = spec["kind"]
    params = dict(spec["params"])
    drop_f = spec.get("drop_f", False)

    if drop_f:
        mask = y_tr != 3
        X_use, y_use = X_tr[mask], y_tr[mask]
    else:
        X_use, y_use = X_tr, y_tr

    if kind == "rf":
        model = RandomForestClassifier(**params)
    elif kind == "et":
        model = ExtraTreesClassifier(**params)
    elif kind == "hgb":
        model = HistGradientBoostingClassifier(**params)
    elif kind == "gb":
        model = GradientBoostingClassifier(**params)
    elif kind == "mlp":
        model = ScaledMLP(**params)
    else:
        raise ValueError(f"unknown model kind: {kind}")

    if spec.get("balanced", True) and kind != "mlp":
        sw = compute_sample_weight("balanced", y_use)
        model.fit(X_use, y_use, sample_weight=sw)
    else:
        model.fit(X_use, y_use)
    return model


def predict_proba_4class(model, X):
    """Map model.predict_proba output onto fixed 4-class columns [N, S, V, F]."""
    proba = np.zeros((len(X), 4), dtype=np.float64)
    proba[:, model.classes_] = model.predict_proba(X)
    return proba


def export_model_json(model, kind, weights, decimals=6):
    """Export any supported candidate model into a plain-loop-friendly JSON dict."""
    classes = [int(c) for c in model.classes_]
    base = {
        "kind": kind,
        "classes": classes,
        "n_classes": 4,
        "decision_weights": [round(float(w), decimals) for w in weights],
    }

    if kind in ("rf", "et"):
        trees = []
        for est in model.estimators_:
            t = est.tree_
            val = t.value[:, 0, :]
            proba = val / val.sum(axis=1, keepdims=True)
            leaf = t.children_left == -1
            trees.append({
                "feature": [-1 if lf else int(f) for f, lf in zip(t.feature, leaf)],
                "threshold": [0.0 if lf else float(th) for th, lf in zip(t.threshold, leaf)],
                "left": [int(v) for v in t.children_left],
                "right": [int(v) for v in t.children_right],
                "value": [np.round(p, decimals).tolist() if lf else None
                          for p, lf in zip(proba, leaf)],
            })
        base["trees"] = trees
        return base

    if kind == "hgb":
        base["baseline"] = [round(float(v), 8) for v in model._baseline_prediction[0]]
        iters = []
        for it_trees in model._predictors:
            cls_trees = []
            for pred in it_trees:
                nd = pred.nodes
                is_leaf = [int(v) for v in nd["is_leaf"]]
                cls_trees.append({
                    "feature": [-1 if lf else int(f) for f, lf in zip(nd["feature_idx"], is_leaf)],
                    "threshold": [0.0 if lf else float(th) for th, lf in zip(nd["num_threshold"], is_leaf)],
                    "left": [-1 if lf else int(l) for l, lf in zip(nd["left"], is_leaf)],
                    "right": [-1 if lf else int(r) for r, lf in zip(nd["right"], is_leaf)],
                    "value": [round(float(val), decimals) if lf else 0.0
                              for val, lf in zip(nd["value"], is_leaf)],
                })
            iters.append(cls_trees)
        base["iterations"] = iters
        return base

    if kind == "gb":
        init_raw = model._raw_predict_init(np.zeros((1, model.n_features_in_)))[0]
        base["baseline"] = [round(float(v), 8) for v in init_raw]
        base["learning_rate"] = float(model.learning_rate)
        stages = []
        for stage in model.estimators_:
            cls_trees = []
            for tree in stage:
                t = tree.tree_
                leaf = t.children_left == -1
                cls_trees.append({
                    "feature": [-1 if lf else int(f) for f, lf in zip(t.feature, leaf)],
                    "threshold": [0.0 if lf else float(th) for th, lf in zip(t.threshold, leaf)],
                    "left": [int(v) for v in t.children_left],
                    "right": [int(v) for v in t.children_right],
                    "value": [round(float(v[0, 0]), decimals) if lf else 0.0
                              for v, lf in zip(t.value, leaf)],
                })
            stages.append(cls_trees)
        base["stages"] = stages
        return base

    if kind == "mlp":
        base["mean"] = [round(float(v), 8) for v in model.scaler.mean_]
        base["scale"] = [round(float(v), 8) for v in model.scaler.scale_]
        base["coefs"] = [np.round(w, decimals).tolist() for w in model.mlp.coefs_]
        base["intercepts"] = [np.round(b, decimals).tolist() for b in model.mlp.intercepts_]
        return base

    raise ValueError(f"unsupported export kind: {kind}")


def _softmax(raw):
    m = max(raw)
    exps = [float(np.exp(v - m)) for v in raw]
    s = sum(exps)
    return [v / s for v in exps]


def json_predict_proba(payload, x):
    """Pure-Python loop prediction from exported JSON payload (1:1 Dart/JS prototype)."""
    kind = payload["kind"]
    classes = payload["classes"]
    k_cls = len(classes)

    if kind in ("rf", "et"):
        xr = np.asarray(x, dtype=np.float32).astype(np.float64).tolist()
        total = [0.0] * k_cls
        for t in payload["trees"]:
            left, right, feat, thr = t["left"], t["right"], t["feature"], t["threshold"]
            i = 0
            while left[i] != -1:
                i = left[i] if xr[feat[i]] <= thr[i] else right[i]
            val = t["value"][i]
            for c in range(k_cls):
                total[c] += val[c]
        n_trees = len(payload["trees"])
        probs = [v / n_trees for v in total]
    elif kind == "hgb":
        xr = [float(v) for v in x]
        raw = list(payload["baseline"])
        for it_trees in payload["iterations"]:
            for c, t in enumerate(it_trees):
                left, right, feat, thr = t["left"], t["right"], t["feature"], t["threshold"]
                i = 0
                while left[i] != -1:
                    i = left[i] if xr[feat[i]] <= thr[i] else right[i]
                raw[c] += t["value"][i]
        probs = _softmax(raw)
    elif kind == "gb":
        xr = np.asarray(x, dtype=np.float32).astype(np.float64).tolist()
        raw = list(payload["baseline"])
        lr = payload["learning_rate"]
        for stage in payload["stages"]:
            for c, t in enumerate(stage):
                left, right, feat, thr = t["left"], t["right"], t["feature"], t["threshold"]
                i = 0
                while left[i] != -1:
                    i = left[i] if xr[feat[i]] <= thr[i] else right[i]
                raw[c] += lr * t["value"][i]
        probs = _softmax(raw)
    elif kind == "mlp":
        mean, scale = payload["mean"], payload["scale"]
        h = [(float(x[j]) - mean[j]) / scale[j] for j in range(len(mean))]
        coefs, intercepts = payload["coefs"], payload["intercepts"]
        for li in range(len(coefs)):
            W, b = coefs[li], intercepts[li]
            n_out = len(b)
            nxt = [0.0] * n_out
            for j in range(n_out):
                s = b[j]
                for i in range(len(h)):
                    s += h[i] * W[i][j]
                if li < len(coefs) - 1 and s < 0.0:
                    s = 0.0
                nxt[j] = s
            h = nxt
        probs = _softmax(h)
    else:
        raise ValueError(f"unsupported payload kind: {kind}")

    out = [0.0, 0.0, 0.0, 0.0]
    for idx_c, cls_id in enumerate(classes):
        out[cls_id] = probs[idx_c]
    return np.asarray(out, dtype=np.float64)


# ---------------------------------------------------------------------------
# Candidate suite
# ---------------------------------------------------------------------------

def get_candidate_specs():
    return [
        {
            "name": "v2.1_baseline_rf",
            "features": "v2.1",
            "kind": "rf",
            "balanced": True,
            "params": {"n_estimators": 50, "min_samples_leaf": 5, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_rf_50_l5",
            "features": "v3",
            "kind": "rf",
            "balanced": True,
            "params": {"n_estimators": 50, "min_samples_leaf": 5, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_rf_80_l5_d16",
            "features": "v3",
            "kind": "rf",
            "balanced": True,
            "params": {"n_estimators": 80, "min_samples_leaf": 5, "max_depth": 16, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_rf_100_l10_d16",
            "features": "v3",
            "kind": "rf",
            "balanced": True,
            "params": {"n_estimators": 100, "min_samples_leaf": 10, "max_depth": 16, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_et_60_l5_d16",
            "features": "v3",
            "kind": "et",
            "balanced": True,
            "params": {"n_estimators": 60, "min_samples_leaf": 5, "max_depth": 16, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_et_100_l5_d18",
            "features": "v3",
            "kind": "et",
            "balanced": True,
            "params": {"n_estimators": 100, "min_samples_leaf": 5, "max_depth": 18, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_et_100_l10_d16",
            "features": "v3",
            "kind": "et",
            "balanced": True,
            "params": {"n_estimators": 100, "min_samples_leaf": 10, "max_depth": 16, "n_jobs": -1, "random_state": SEED},
        },
        {
            "name": "v3_hgb_100_l15_bal",
            "features": "v3",
            "kind": "hgb",
            "balanced": True,
            "params": {"max_iter": 100, "max_leaf_nodes": 15, "learning_rate": 0.08,
                       "min_samples_leaf": 30, "l2_regularization": 1.0, "random_state": SEED},
        },
        {
            "name": "v3_hgb_150_l15_bal",
            "features": "v3",
            "kind": "hgb",
            "balanced": True,
            "params": {"max_iter": 150, "max_leaf_nodes": 15, "learning_rate": 0.05,
                       "min_samples_leaf": 40, "l2_regularization": 2.0, "random_state": SEED},
        },
        {
            "name": "v3_hgb_150_l31_bal",
            "features": "v3",
            "kind": "hgb",
            "balanced": True,
            "params": {"max_iter": 150, "max_leaf_nodes": 31, "learning_rate": 0.05,
                       "min_samples_leaf": 50, "l2_regularization": 5.0, "random_state": SEED},
        },
        {
            "name": "v3_hgb_120_l15_unw",
            "features": "v3",
            "kind": "hgb",
            "balanced": False,
            "params": {"max_iter": 120, "max_leaf_nodes": 15, "learning_rate": 0.06,
                       "min_samples_leaf": 30, "l2_regularization": 2.0, "random_state": SEED},
        },
        {
            "name": "v3_gb_30_d3_bal",
            "features": "v3",
            "kind": "gb",
            "balanced": True,
            "params": {"n_estimators": 30, "max_depth": 3, "learning_rate": 0.1,
                       "subsample": 0.5, "max_features": "sqrt", "random_state": SEED},
        },
        {
            "name": "v3_mlp_64_32_unw",
            "features": "v3",
            "kind": "mlp",
            "balanced": False,
            "params": {"hidden_layer_sizes": (64, 32), "alpha": 1e-2, "max_iter": 50,
                       "oversample_ratio": 0.0, "random_state": SEED},
        },
        {
            "name": "v3_mlp_64_32_ovs",
            "features": "v3",
            "kind": "mlp",
            "balanced": False,
            "params": {"hidden_layer_sizes": (64, 32), "alpha": 1e-2, "max_iter": 50,
                       "oversample_ratio": 0.15, "random_state": SEED},
        },
    ]


# ---------------------------------------------------------------------------
# End-to-end signal evaluation & Pan-Tompkins 0.2x prototype
# ---------------------------------------------------------------------------

def detect_rpeaks_v3_proto(xf, sos_det, fs=FS, use_fast_filter=False):
    """Prototype Pan-Tompkins detector with spki_ref-floored decay and conditional multi-beat rescue."""
    xf = np.asarray(xf, dtype=float)
    n = len(xf)
    if n < 5:
        return np.array([], dtype=int)
    det = fast_filtfilt_sos(sos_det, xf) if use_fast_filter else portable.filtfilt(sos_det, xf)

    d = np.zeros(n)
    d[2:n - 2] = (2 * det[4:] + det[3:n - 1] - det[1:n - 3] - 2 * det[:n - 4]) * fs / 8
    sq = d * d
    half = int(0.15 * fs) // 2
    c = np.concatenate([[0.0], np.cumsum(sq)])
    idx = np.arange(n)
    lo = np.maximum(idx - half, 0)
    hi = np.minimum(idx + half + 1, n)
    mwi = (c[hi] - c[lo]) / (hi - lo)

    cand = (np.flatnonzero((mwi[1:-1] > mwi[:-2]) & (mwi[1:-1] >= mwi[2:])) + 1).tolist()

    refr = int(0.2 * fs)
    init_end = min(n, 8 * fs)
    block = 2 * fs
    block_max = [float(np.max(mwi[i:min(i + block, init_end)])) for i in range(0, init_end, block)]
    block_max = [v for v in block_max if v > 0]
    spki = float(np.median(block_max)) if block_max else 0.0
    npki = float(np.median(mwi[:init_end])) if init_end > 0 else 0.0
    if npki > spki:
        npki = 0.5 * spki
    spki_ref = spki

    accepted = []
    rejected = []
    rj = 0
    silence_thresh = int(2.5 * fs)
    decay_step = int(0.5 * fs)
    last_decay_pos = 0
    did_decay = False

    def _rescue_single(lo_pos, hi_pos, min_peak_thr, rj_ptr):
        while rj_ptr < len(rejected) and rejected[rj_ptr][0] < lo_pos:
            rj_ptr += 1
        best = None
        j = rj_ptr
        while j < len(rejected) and rejected[j][0] <= hi_pos:
            if rejected[j][1] > min_peak_thr and (best is None or rejected[j][1] > best[1]):
                best = rejected[j]
            j += 1
        return ([best] if best is not None else []), rj_ptr

    def _rescue_gap(lo_pos, hi_pos, min_peak_thr, rj_ptr):
        while rj_ptr < len(rejected) and rejected[rj_ptr][0] < lo_pos:
            rj_ptr += 1
        pool = []
        j = rj_ptr
        while j < len(rejected) and rejected[j][0] <= hi_pos:
            if rejected[j][1] > min_peak_thr:
                pool.append(rejected[j])
            j += 1
        if not pool:
            return [], rj_ptr

        pool.sort(key=lambda item: -item[1])
        rescued = []
        for pos_r, h_r in pool:
            if any(abs(pos_r - rp) < refr for rp, _ in rescued):
                continue
            rescued.append([pos_r, h_r])
        rescued.sort(key=lambda item: item[0])
        return rescued, rj_ptr

    for ci in cand:
        # Controlled spki decay after prolonged silence (>2.5 s) floored at 0.08 * spki_ref
        # so 0.2x amplitude drops (~0.04 * spki_ref) recover while asystolic pauses stay quiet.
        if accepted and ci - last_decay_pos > silence_thresh:
            while ci - last_decay_pos > silence_thresh:
                spki = max(0.5 * spki, 2.0 * npki, 0.08 * spki_ref)
                last_decay_pos += decay_step
                did_decay = True

        h = mwi[ci]
        thr = npki + 0.25 * (spki - npki)
        if h > thr:
            if accepted and ci - accepted[-1][0] < refr:
                if h > accepted[-1][1]:
                    accepted[-1] = [ci, h]
                    last_decay_pos = ci
                continue
            if len(accepted) > 8:
                rr = float(np.mean(np.diff([a[0] for a in accepted[-9:]])))
                gap = ci - accepted[-1][0]
                if gap > 1.66 * rr:
                    lo_pos = accepted[-1][0] + refr
                    hi_pos = ci - refr
                    if gap <= 2.2 * rr and not did_decay:
                        rescued, rj = _rescue_single(lo_pos, hi_pos, 0.5 * thr, rj)
                    else:
                        min_thr = max(0.5 * thr, 0.015 * spki_ref)
                        rescued, rj = _rescue_gap(lo_pos, hi_pos, min_thr, rj)
                    accepted.extend(rescued)
            accepted.append([ci, h])
            last_decay_pos = ci
            spki = 0.125 * (min(h, 4.0 * spki) if spki > 0 else h) + 0.875 * spki
            if not did_decay:
                spki_ref = 0.02 * (min(h, 4.0 * spki_ref) if spki_ref > 0 else h) + 0.98 * spki_ref
            did_decay = False
        else:
            rejected.append([ci, h])
            npki = 0.125 * h + 0.875 * npki

    # Final tail check if the end of recording had an amplitude drop with no recovery beat.
    if len(accepted) > 8 and n - accepted[-1][0] > silence_thresh:
        tail_pos = accepted[-1][0]
        spki_tail = spki
        while n - max(last_decay_pos, tail_pos) > silence_thresh:
            spki_tail = max(0.5 * spki_tail, 2.0 * npki, 0.08 * spki_ref)
            last_decay_pos += decay_step
        thr_tail = npki + 0.25 * (spki_tail - npki)
        rescued, _ = _rescue_gap(tail_pos + refr, n - refr, max(0.5 * thr_tail, 0.015 * spki_ref), rj)
        accepted.extend(rescued)

    w = int(0.08 * fs)
    peaks = []
    for pos, _ in accepted:
        a, b = max(0, pos - w), min(n, pos + w + 1)
        peaks.append(a + int(np.argmax(np.abs(xf[a:b]))))

    out = []
    for p in sorted(peaks):
        if out and p - out[-1] < refr:
            if abs(xf[p]) > abs(xf[out[-1]]):
                out[-1] = p
            continue
        out.append(p)
    return np.array(out, dtype=int)


def evaluate_end_to_end(records, model, weights, feature_mode, sos_main, sos_det,
                        detector_fn=None, tolerance=36, use_fast_filter=False):
    """Run raw-signal pipeline on `records` and match detected peaks to MIT-BIH atr."""
    y_true, y_pred, offsets = [], [], []
    n_ann = n_det = n_tp = 0
    total_sec = 0.0

    for rec_id in records:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec_id)))
        ann = wfdb.rdann(os.path.join(DATA_DIR, str(rec_id)), "atr")
        ch = record.sig_name.index("MLII")
        raw_sig = record.p_signal[:, ch]

        t0 = time.perf_counter()
        sig = portable.sanitize_signal(raw_sig, record.fs)
        sig = portable.to_360hz(sig, record.fs)
        sig_f = fast_filtfilt_sos(sos_main, sig) if use_fast_filter else portable.filtfilt(sos_main, sig)
        if detector_fn is None:
            peaks = (
                portable.detect_rpeaks(sig_f, sos_det)
                if not use_fast_filter
                else _detect_rpeaks_fast(sig_f, sos_det)
            )
        else:
            peaks = detector_fn(sig_f, sos_det)

        beats, rr, used = [], [], []
        for k in range(1, len(peaks) - 1):
            p = int(peaks[k])
            if p - PRE < 0 or p + POST > len(sig_f):
                continue
            beats.append(sig_f[p - PRE:p + POST])
            rr.append([int(peaks[k] - peaks[k - 1]), int(peaks[k + 1] - peaks[k])])
            used.append(p)

        if beats:
            beats_arr = np.asarray(beats, dtype=np.float64)
            rr_arr = np.asarray(rr, dtype=np.float64)
            if feature_mode == "v2.1":
                F = features_v2.build_features(beats_arr, rr_arr, np.zeros(len(beats_arr), dtype=int))
            else:
                F = features_v3.extract_recording_features_v3(beats_arr, rr_arr)
            proba = predict_proba_4class(model, F)
            pred = (proba * weights).argmax(1)
        else:
            pred = np.array([], dtype=int)
        total_sec += time.perf_counter() - t0

        keep = [i for i, s in enumerate(ann.symbol) if s in AAMI_ALL]
        a_samples = ann.sample[keep]
        a_labels = [AAMI_ALL[ann.symbol[i]] for i in keep]

        n_ann += len(a_samples)
        n_det += len(used)
        for p, c in zip(used, pred):
            j = int(np.argmin(np.abs(a_samples - p)))
            if abs(int(a_samples[j]) - int(p)) <= tolerance:
                n_tp += 1
                offsets.append(int(a_samples[j]) - int(p))
                if a_labels[j] in CLASSES:
                    y_true.append(CLASSES.index(a_labels[j]))
                    y_pred.append(int(c))

    metrics = compute_metrics(np.asarray(y_true), np.asarray(y_pred))
    metrics.update({
        "annotated": int(n_ann),
        "detected": int(n_det),
        "matched": int(n_tp),
        "sensitivity": float(n_tp / n_ann),
        "positive_predictivity": float(n_tp / n_det) if n_det else 0.0,
        "offset_percentiles_5_50_95": [float(v) for v in np.percentile(offsets, [5, 50, 95])],
        "total_seconds": round(total_sec, 2),
    })
    return metrics


def _detect_rpeaks_fast(xf, sos_det, fs=FS):
    """Exact equivalent of portable.detect_rpeaks using scipy_sosfilt for sos_det."""
    xf = np.asarray(xf, dtype=float)
    n = len(xf)
    if n < 5:
        return np.array([], dtype=int)
    det = fast_filtfilt_sos(sos_det, xf)

    d = np.zeros(n)
    d[2:n - 2] = (2 * det[4:] + det[3:n - 1] - det[1:n - 3] - 2 * det[:n - 4]) * fs / 8
    sq = d * d
    half = int(0.15 * fs) // 2
    c = np.concatenate([[0.0], np.cumsum(sq)])
    idx = np.arange(n)
    lo = np.maximum(idx - half, 0)
    hi = np.minimum(idx + half + 1, n)
    mwi = (c[hi] - c[lo]) / (hi - lo)

    cand = (np.flatnonzero((mwi[1:-1] > mwi[:-2]) & (mwi[1:-1] >= mwi[2:])) + 1).tolist()
    refr = int(0.2 * fs)
    init_end = min(n, 8 * fs)
    block = 2 * fs
    block_max = [float(np.max(mwi[i:min(i + block, init_end)])) for i in range(0, init_end, block)]
    block_max = [v for v in block_max if v > 0]
    spki = float(np.median(block_max)) if block_max else 0.0
    npki = float(np.median(mwi[:init_end])) if init_end > 0 else 0.0
    if npki > spki:
        npki = 0.5 * spki

    accepted, rejected, rj = [], [], 0
    for ci in cand:
        h = mwi[ci]
        thr = npki + 0.25 * (spki - npki)
        if h > thr:
            if accepted and ci - accepted[-1][0] < refr:
                if h > accepted[-1][1]:
                    accepted[-1] = [ci, h]
                continue
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
            spki = 0.125 * (min(h, 4.0 * spki) if spki > 0 else h) + 0.875 * spki
        else:
            rejected.append([ci, h])
            npki = 0.125 * h + 0.875 * npki

    w = int(0.08 * fs)
    peaks = [max(0, pos - w) + int(np.argmax(np.abs(xf[max(0, pos - w):min(n, pos + w + 1)])))
             for pos, _ in accepted]
    out = []
    for p in sorted(peaks):
        if out and p - out[-1] < refr:
            if abs(xf[p]) > abs(xf[out[-1]]):
                out[-1] = p
            continue
        out.append(p)
    return np.array(out, dtype=int)


def benchmark_detector_only(records, detector_fn, sos_main, sos_det, tolerance=36):
    """Measure R-peak detection Sensitivity and Positive Predictivity across records."""
    n_ann = n_det = n_tp = 0
    for rec_id in records:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec_id)))
        ann = wfdb.rdann(os.path.join(DATA_DIR, str(rec_id)), "atr")
        ch = record.sig_name.index("MLII")
        sig_f = fast_filtfilt_sos(sos_main, record.p_signal[:, ch])
        peaks = detector_fn(sig_f, sos_det)

        keep = [i for i, s in enumerate(ann.symbol) if s in AAMI_ALL]
        a_samples = ann.sample[keep]
        n_ann += len(a_samples)
        n_det += len(peaks)
        for p in peaks:
            j = int(np.argmin(np.abs(a_samples - p)))
            if abs(int(a_samples[j]) - int(p)) <= tolerance:
                n_tp += 1

    return {
        "annotated": int(n_ann),
        "detected": int(n_det),
        "matched": int(n_tp),
        "sensitivity": float(n_tp / n_ann),
        "positive_predictivity": float(n_tp / n_det) if n_det else 0.0,
    }


def evaluate_svdb_external(v21_bundle, v3_model, v3_weights, sos_main, limit=15):
    """Optional external evaluation on PhysioNet SVDB (zero retraining)."""
    import socket

    old_timeout = socket.getdefaulttimeout()
    socket.setdefaulttimeout(15)
    try:
        req = urllib.request.Request(
            "https://physionet.org/files/svdb/1.0.0/RECORDS",
            headers={"User-Agent": "ecg-v3-research/1.0"},
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            rec_names = [line.strip() for line in resp.read().decode("utf-8").splitlines() if line.strip()]
    except Exception as exc:
        socket.setdefaulttimeout(old_timeout)
        return {"status": "skipped", "reason": f"PhysioNet SVDB unreachable ({exc})"}

    svdb_dir = os.path.join(ROOT, "data", "svdb")
    os.makedirs(svdb_dir, exist_ok=True)
    subset = rec_names[:limit]

    try:
        missing = [r for r in subset if not os.path.exists(os.path.join(svdb_dir, f"{r}.hea"))]
        if missing:
            wfdb.dl_database("svdb", dl_dir=svdb_dir, records=missing, keep_subdirs=False, overwrite=False)
    except Exception as exc:
        socket.setdefaulttimeout(old_timeout)
        return {"status": "skipped", "reason": f"SVDB download failed ({exc})"}
    finally:
        socket.setdefaulttimeout(old_timeout)

    X_parts, y_parts, rr_parts, g_parts = [], [], [], []
    used_recs = []
    for rec_idx, rec_id in enumerate(subset):
        try:
            rec = wfdb.rdrecord(os.path.join(svdb_dir, rec_id))
            ann = wfdb.rdann(os.path.join(svdb_dir, rec_id), "atr")
        except Exception:
            continue
        sig_360 = portable.to_360hz(rec.p_signal[:, 0], rec.fs)
        sig_f = fast_filtfilt_sos(sos_main, sig_360)
        ratio = FS / float(rec.fs)

        keep = [i for i, sym in enumerate(ann.symbol) if sym in AAMI_ALL]
        samples = np.round(ann.sample[keep] * ratio).astype(int)
        labels = [AAMI_ALL[ann.symbol[i]] for i in keep]

        Xr, yr, rrr = [], [], []
        for k in range(1, len(samples) - 1):
            p = int(samples[k])
            if p - PRE < 0 or p + POST > len(sig_f):
                continue
            if labels[k] == "Q":
                continue
            Xr.append(sig_f[p - PRE:p + POST])
            yr.append(CLASSES.index(labels[k]))
            rrr.append([int(samples[k] - samples[k - 1]), int(samples[k + 1] - samples[k])])

        if Xr:
            used_recs.append(rec_id)
            X_parts.append(np.asarray(Xr, dtype=np.float64))
            y_parts.append(np.asarray(yr, dtype=np.int64))
            rr_parts.append(np.asarray(rrr, dtype=np.int64))
            g_parts.append(np.full(len(yr), rec_idx, dtype=np.int64))

    if not X_parts:
        return {"status": "skipped", "reason": "No valid SVDB beats extracted"}

    X_sv = np.concatenate(X_parts)
    y_sv = np.concatenate(y_parts)
    rr_sv = np.concatenate(rr_parts)
    g_sv = np.concatenate(g_parts)

    F_v21_sv = features_v2.build_features(X_sv, rr_sv, g_sv)
    F_v3_sv = features_v3.build_features_v3(X_sv, rr_sv, g_sv)

    p21 = predict_proba_4class(v21_bundle["model"], F_v21_sv)
    w21 = np.asarray(v21_bundle["decision_weights"], dtype=float)
    m21 = compute_metrics(y_sv, (p21 * w21).argmax(1))

    p3 = predict_proba_4class(v3_model, F_v3_sv)
    m3 = compute_metrics(y_sv, (p3 * v3_weights).argmax(1))

    return {
        "status": "completed",
        "records": len(used_recs),
        "beats": int(len(y_sv)),
        "class_counts": {CLASSES[c]: int((y_sv == c).sum()) for c in range(4)},
        "v2.1": m21,
        "v3": m3,
    }


def run_detector_prototype_benchmark(sig_200, sos_main, sos_det):
    """Run record_200 0.2x drop test and MIT-BIH DS1/DS2 detector benchmark."""
    print("\n=== Pan-Tompkins 0.2x Mid-Recording Drop Prototype ===")
    sig_drop = sig_200.copy()
    mid = len(sig_drop) // 2
    sig_drop[mid:] *= 0.2
    xf_clean = portable.filtfilt(sos_main, sig_200)
    xf_drop = portable.filtfilt(sos_main, sig_drop)

    pk_clean_v21 = portable.detect_rpeaks(xf_clean, sos_det)
    pk_drop_v21 = portable.detect_rpeaks(xf_drop, sos_det)
    pk_drop_v3 = detect_rpeaks_v3_proto(xf_drop, sos_det, use_fast_filter=False)

    half2_clean = int((pk_clean_v21 >= mid).sum())
    half2_drop_v21 = int((pk_drop_v21 >= mid).sum())
    half2_drop_v3 = int((pk_drop_v3 >= mid).sum())

    det_ds1_v21 = benchmark_detector_only(DS1, _detect_rpeaks_fast, sos_main, sos_det)
    det_ds1_v3 = benchmark_detector_only(DS1, lambda xf, sd: detect_rpeaks_v3_proto(xf, sd, use_fast_filter=True), sos_main, sos_det)
    det_ds2_v21 = benchmark_detector_only(DS2, _detect_rpeaks_fast, sos_main, sos_det)
    det_ds2_v3 = benchmark_detector_only(DS2, lambda xf, sd: detect_rpeaks_v3_proto(xf, sd, use_fast_filter=True), sos_main, sos_det)

    detector_proto = {
        "record_200_0.2x_second_half": {
            "clean_second_half_peaks": half2_clean,
            "v2.1_second_half_peaks": half2_drop_v21,
            "v3_proto_second_half_peaks": half2_drop_v3,
            "v2.1_total_peaks": int(len(pk_drop_v21)),
            "v3_proto_total_peaks": int(len(pk_drop_v3)),
        },
        "DS1": {"v2.1": det_ds1_v21, "v3_proto": det_ds1_v3},
        "DS2": {"v2.1": det_ds2_v21, "v3_proto": det_ds2_v3},
    }
    print(f"  record_200 2nd-half 0.2x: clean={half2_clean} | v2.1={half2_drop_v21} | v3_proto={half2_drop_v3}")
    print(f"  DS1 detector: v2.1 Sens={det_ds1_v21['sensitivity']:.4f} PPV={det_ds1_v21['positive_predictivity']:.4f} | "
          f"v3_proto Sens={det_ds1_v3['sensitivity']:.4f} PPV={det_ds1_v3['positive_predictivity']:.4f}")
    print(f"  DS2 detector: v2.1 Sens={det_ds2_v21['sensitivity']:.4f} PPV={det_ds2_v21['positive_predictivity']:.4f} | "
          f"v3_proto Sens={det_ds2_v3['sensitivity']:.4f} PPV={det_ds2_v3['positive_predictivity']:.4f}")
    return detector_proto


def compute_ds2_rec232_breakdown(y_ds2, g_ds2, pred_v21, pred_v3):
    """Post-hoc read-only breakdown of DS2 S-class performance with/without record 232."""
    out = {}
    for label, mask in [
        ("all_22_records", np.ones(len(y_ds2), dtype=bool)),
        ("excl_rec_232_21_records", g_ds2 != 232),
        ("rec_232_only", g_ds2 == 232),
    ]:
        out[label] = {
            "v2.1": compute_metrics(y_ds2[mask], pred_v21[mask]),
            "v3": compute_metrics(y_ds2[mask], pred_v3[mask]),
        }
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--skip-svdb", action="store_true", help="skip PhysioNet SVDB network probe")
    ap.add_argument("--svdb-limit", type=int, default=20, help="max SVDB records to evaluate")
    ap.add_argument("--detector-only", action="store_true",
                    help="only re-run detector 0.2x prototype + DS2 rec 232 diagnostic and update json-out")
    ap.add_argument("--json-out", default=os.path.join(ROOT, "docs", "v3_experiment_results.json"))
    args = ap.parse_args()

    t_start = time.perf_counter()
    sos_main, sos_det = portable.make_sos()
    rec200_path = os.path.join(ROOT, "app", "samples", "record_200.csv")
    with open(rec200_path, encoding="utf-8-sig") as handle:
        sig_200 = read_signal_frame(handle.read())["MLII_mV"].to_numpy(dtype=float)

    if args.detector_only:
        with open(args.json_out, encoding="utf-8") as handle:
            summary = json.load(handle)
        detector_proto = run_detector_prototype_benchmark(sig_200, sos_main, sos_det)
        summary["detector_0.2x_prototype"] = detector_proto

        # Also record the read-only post-hoc DS2 record 232 breakdown using the frozen winner.
        X_ds1, y_ds1, rr_ds1, g_ds1, _ = load_mitdb_split(DS1)
        X_ds2, y_ds2, rr_ds2, g_ds2, _ = load_mitdb_split(DS2)
        F_v21_ds2 = features_v2.build_features(X_ds2, rr_ds2, g_ds2)
        F_v3_ds1 = features_v3.build_features_v3(X_ds1, rr_ds1, g_ds1)
        F_v3_ds2 = features_v3.build_features_v3(X_ds2, rr_ds2, g_ds2)

        v21_bundle = joblib.load(os.path.join(ROOT, "models", "ecg_rf_small.joblib"))
        pred_v21 = (predict_proba_4class(v21_bundle["model"], F_v21_ds2)
                    * np.asarray(v21_bundle["decision_weights"], dtype=float)).argmax(1)

        winner_name = summary["winner"]["name"]
        winner_weights = np.asarray(summary["winner"]["weights"], dtype=float)
        base_name = winner_name[:-5] if winner_name.endswith("_3cls") else winner_name
        winner_spec = dict([s for s in get_candidate_specs() if s["name"] == base_name][0])
        winner_spec["name"] = winner_name
        winner_spec["drop_f"] = winner_name.endswith("_3cls")
        winner_model = fit_candidate(winner_spec, F_v3_ds1, y_ds1)
        pred_v3 = (predict_proba_4class(winner_model, F_v3_ds2) * winner_weights).argmax(1)
        summary["ds2_rec232_breakdown"] = compute_ds2_rec232_breakdown(y_ds2, g_ds2, pred_v21, pred_v3)

        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(summary, handle, indent=1)
        print(f"\nUpdated {args.json_out} ({os.path.getsize(args.json_out)} bytes) in {time.perf_counter()-t_start:.2f}s")
        return

    print("=== Loading MIT-BIH DS1 (train) and DS2 (locked test) ===")
    X_ds1, y_ds1, rr_ds1, g_ds1, s_ds1 = load_mitdb_split(DS1)
    X_ds2, y_ds2, rr_ds2, g_ds2, s_ds2 = load_mitdb_split(DS2)
    verify_split_integrity(X_ds1, y_ds1, rr_ds1, g_ds1, X_ds2, y_ds2, rr_ds2, g_ds2)
    print(f"DS1: {X_ds1.shape} counts={ {CLASSES[c]: int((y_ds1==c).sum()) for c in range(4)} }")
    print(f"DS2: {X_ds2.shape} counts={ {CLASSES[c]: int((y_ds2==c).sum()) for c in range(4)} } (LOCKED)")

    # Check fast_filtfilt_sos parity against portable.filtfilt on record_200.csv.
    assert np.max(np.abs(portable.filtfilt(sos_main, sig_200) - fast_filtfilt_sos(sos_main, sig_200))) < 1e-12
    assert np.array_equal(
        portable.detect_rpeaks(portable.filtfilt(sos_main, sig_200), sos_det),
        _detect_rpeaks_fast(fast_filtfilt_sos(sos_main, sig_200), sos_det),
    )

    # -----------------------------------------------------------------------
    # Phase A: All model selection & tuning strictly inside DS1 5-fold CV
    # -----------------------------------------------------------------------
    ablation_ds1 = build_ablation_matrices(X_ds1, rr_ds1, g_ds1)
    F_v21_ds1 = ablation_ds1["v2.1_baseline_57"]
    F_v3_ds1 = ablation_ds1["v3_full_84"]

    sgkf = StratifiedGroupKFold(n_splits=5)
    folds = list(sgkf.split(F_v3_ds1, y_ds1, g_ds1))
    fold_summary = []
    print("\n=== DS1 5-fold StratifiedGroupKFold Summary ===")
    for fi, (_, va) in enumerate(folds):
        c = np.bincount(y_ds1[va], minlength=4)
        recs = sorted(np.unique(g_ds1[va]).tolist())
        info = {"fold": fi, "records": recs, "counts": {CLASSES[i]: int(c[i]) for i in range(4)}}
        fold_summary.append(info)
        print(f"  Fold {fi}: recs={recs} | N={c[0]:5d} S={c[1]:3d} V={c[2]:4d} F={c[3]:3d}")

    cv_cache = {}

    def run_cv_cached(cache_key, spec, F_mat, keep_models=False):
        if cache_key in cv_cache:
            return cv_cache[cache_key]
        oof = np.zeros((len(y_ds1), 4), dtype=np.float64)
        models = []
        for tr, va in folds:
            m = fit_candidate(spec, F_mat[tr], y_ds1[tr])
            oof[va] = predict_proba_4class(m, F_mat[va])
            if keep_models:
                models.append(m)
        res = evaluate_oof_folds(oof, y_ds1, g_ds1, folds)
        cv_cache[cache_key] = (oof, models, res)
        return oof, models, res

    # 1) Class F proof strictly on DS1 CV
    print("\n=== Class F Check on DS1 OOF ===")
    f_patient_208 = int((y_ds1[g_ds1 == 208] == 3).sum())
    f_total_ds1 = int((y_ds1 == 3).sum())
    print(f"DS1 class F beats: {f_total_ds1} total, {f_patient_208} ({100*f_patient_208/f_total_ds1:.1f}%) in patient 208 alone.")
    f_check_results = {}
    rf50_spec = {"name": "v2.1_baseline_rf", "features": "v2.1", "kind": "rf", "balanced": True,
                 "params": {"n_estimators": 50, "min_samples_leaf": 5, "n_jobs": -1, "random_state": SEED}}
    hgb120_spec = {"name": "v3_hgb120_l15_bal", "features": "v3", "kind": "hgb", "balanced": True,
                   "params": {"max_iter": 120, "max_leaf_nodes": 15, "learning_rate": 0.06,
                              "min_samples_leaf": 30, "l2_regularization": 2.0, "random_state": SEED}}
    for label, cache_key, spec_f, feat_mat, keep_m in [
        ("v2.1_rf50", ("v2.1_baseline_57", "rf50"), rf50_spec, F_v21_ds1, True),
        ("v3_hgb120_l15", ("v3_full_84", "hgb120_bal"), hgb120_spec, F_v3_ds1, False),
    ]:
        oof_f, _, _ = run_cv_cached(cache_key, spec_f, feat_mat, keep_models=keep_m)
        w_f, _ = tune_weights_with_f(oof_f, y_ds1)
        m_with_f = compute_metrics(y_ds1, (oof_f * w_f).argmax(1))
        w_nof, _ = tune_weights_nsv(oof_f, y_ds1)
        m_no_f = compute_metrics(y_ds1, (oof_f * w_nof).argmax(1))
        f_check_results[label] = {
            "with_F": {"weights": w_f.tolist(), "metrics": m_with_f},
            "drop_F_weight": {"weights": w_nof.tolist(), "metrics": m_no_f},
        }
        print(
            f"  {label} | tune w_F: w={w_f.tolist()} F_prec={m_with_f['per_class']['F']['precision']:.3f} "
            f"F_rec={m_with_f['per_class']['F']['recall']:.3f} F_f1={m_with_f['per_class']['F']['f1']:.3f} "
            f"macro_NSV={m_with_f['macro_f1_nsv']:.3f} | w_F=0: macro_NSV={m_no_f['macro_f1_nsv']:.3f}"
        )

    # 2) Feature ablation on DS1 CV
    print("\n=== DS1 CV Feature Ablation ===")
    ablation_specs = {
        "RF(50, leaf=5)": ("rf50", rf50_spec),
        "HGB(120, leaf=15)": ("hgb120_bal", hgb120_spec),
    }
    ablation_results = {}
    for model_label, (short_key, m_spec) in ablation_specs.items():
        ablation_results[model_label] = {}
        for feat_name, F_mat in ablation_ds1.items():
            keep_m = (feat_name == "v2.1_baseline_57" and short_key == "rf50") or (feat_name == "v3_full_84" and short_key == "rf50")
            _, _, res = run_cv_cached((feat_name, short_key), m_spec, F_mat, keep_models=keep_m)
            ablation_results[model_label][feat_name] = res
            m_oof = res["oof_metrics"]
            print(
                f"  [{model_label:17s}] {feat_name:40s} | "
                f"N={m_oof['per_class']['N']['f1']:.3f} "
                f"S={m_oof['per_class']['S']['f1']:.3f} "
                f"V={m_oof['per_class']['V']['f1']:.3f} | "
                f"Macro(NSV)={m_oof['macro_f1_nsv']:.3f} "
                f"(fold {res['fold_macro_mean']:.3f}±{res['fold_macro_std']:.3f}) | "
                f"w={res['weights']}"
            )

    # 3) Model family comparison on DS1 CV
    print("\n=== DS1 CV Model Family Comparison ===")
    candidates = get_candidate_specs()
    candidate_results = []
    parity_probe = F_v3_ds1[:300]
    parity_probe_v21 = F_v21_ds1[:300]
    fold_models_by_name = {}

    for spec in candidates:
        name = spec["name"]
        F_mat = F_v21_ds1 if spec["features"] == "v2.1" else F_v3_ds1
        probe = parity_probe_v21 if spec["features"] == "v2.1" else parity_probe

        if name == "v2.1_baseline_rf":
            c_key = ("v2.1_baseline_57", "rf50")
        elif name == "v3_rf_50_l5":
            c_key = ("v3_full_84", "rf50")
        else:
            c_key = ("v3_full_84", name)

        oof, fold_models, res = run_cv_cached(c_key, spec, F_mat, keep_models=True)
        fold_models_by_name[name] = fold_models
        w = np.asarray(res["weights"], dtype=float)

        # Fit once on DS1 to check exact JSON size, portable loop parity, and inference speed.
        full_model = fit_candidate(spec, F_mat, y_ds1)
        payload = export_model_json(full_model, spec["kind"], w)
        json_str = json.dumps(payload, separators=(",", ":"))
        json_bytes = len(json_str.encode("utf-8"))

        sk_p = predict_proba_4class(full_model, probe)
        loop_p = np.asarray([json_predict_proba(payload, row) for row in probe])
        max_parity_diff = float(np.max(np.abs(sk_p - loop_p)))

        t0 = time.perf_counter()
        _ = predict_proba_4class(full_model, F_mat[:2000])
        sk_ms_1k = (time.perf_counter() - t0) * 500.0

        t1 = time.perf_counter()
        _ = [json_predict_proba(payload, row) for row in probe]
        loop_ms_1k = (time.perf_counter() - t1) * (1000.0 / len(probe))

        entry = {
            "name": name,
            "features": spec["features"],
            "kind": spec["kind"],
            "balanced": spec["balanced"],
            "drop_f": spec.get("drop_f", False),
            "params": {k: (list(v) if isinstance(v, tuple) else v) for k, v in spec["params"].items()},
            "json_bytes": json_bytes,
            "json_mb": round(json_bytes / 1e6, 3),
            "parity_max_diff": max_parity_diff,
            "sklearn_ms_per_1k": round(sk_ms_1k, 2),
            "loop_ms_per_1k": round(loop_ms_1k, 2),
            **res,
        }
        candidate_results.append(entry)
        m_oof = res["oof_metrics"]
        print(
            f"  {name:22s} | N={m_oof['per_class']['N']['f1']:.3f} "
            f"S={m_oof['per_class']['S']['f1']:.3f} V={m_oof['per_class']['V']['f1']:.3f} | "
            f"Macro={m_oof['macro_f1_nsv']:.3f} (nested={res['nested_macro_f1_nsv']:.3f}) | "
            f"JSON={entry['json_mb']:.3f}MB parity={max_parity_diff:.1e} loop={entry['loop_ms_per_1k']:.1f}ms/1k"
        )

    # Also test 3-class training (drop F from fit only) on the top 2 v3 candidates.
    top2_v3 = sorted(
        [c for c in candidate_results if c["features"] == "v3" and c["json_mb"] <= 3.0],
        key=lambda r: r["oof_metrics"]["macro_f1_nsv"],
        reverse=True,
    )[:2]
    print("\n=== DS1 CV 3-Class Fit Check (drop F from fit only, still score all 50,969 beats) ===")
    spec_by_name = {s["name"]: s for s in candidates}
    for base_entry in top2_v3:
        spec3 = dict(spec_by_name[base_entry["name"]])
        spec3["name"] = base_entry["name"] + "_3cls"
        spec3["drop_f"] = True
        oof3, fold_models3, res3 = run_cv_cached(("v3_full_84", spec3["name"]), spec3, F_v3_ds1, keep_models=True)
        fold_models_by_name[spec3["name"]] = fold_models3
        w3 = np.asarray(res3["weights"], dtype=float)
        full_m3 = fit_candidate(spec3, F_v3_ds1, y_ds1)
        payload3 = export_model_json(full_m3, spec3["kind"], w3)
        json_bytes3 = len(json.dumps(payload3, separators=(",", ":")).encode("utf-8"))
        sk_p3 = predict_proba_4class(full_m3, parity_probe)
        loop_p3 = np.asarray([json_predict_proba(payload3, row) for row in parity_probe])
        max_parity_diff3 = float(np.max(np.abs(sk_p3 - loop_p3)))
        t1 = time.perf_counter()
        _ = [json_predict_proba(payload3, row) for row in parity_probe]
        loop_ms3 = (time.perf_counter() - t1) * (1000.0 / len(parity_probe))

        entry3 = {
            "name": spec3["name"],
            "features": "v3",
            "kind": spec3["kind"],
            "balanced": spec3["balanced"],
            "drop_f": True,
            "params": base_entry["params"],
            "json_bytes": json_bytes3,
            "json_mb": round(json_bytes3 / 1e6, 3),
            "parity_max_diff": max_parity_diff3,
            "sklearn_ms_per_1k": base_entry["sklearn_ms_per_1k"],
            "loop_ms_per_1k": round(loop_ms3, 2),
            **res3,
        }
        candidate_results.append(entry3)
        spec_by_name[spec3["name"]] = spec3
        m_oof3 = res3["oof_metrics"]
        print(
            f"  {spec3['name']:26s} | N={m_oof3['per_class']['N']['f1']:.3f} "
            f"S={m_oof3['per_class']['S']['f1']:.3f} V={m_oof3['per_class']['V']['f1']:.3f} | "
            f"Macro={m_oof3['macro_f1_nsv']:.3f} (nested={res3['nested_macro_f1_nsv']:.3f}) | "
            f"JSON={entry3['json_mb']:.3f}MB"
        )

    # 4) Short-clip stability on DS1 CV (30-min vs 60s vs 15s) using cached fold models
    print("\n=== DS1 CV Short-Clip Stability (30-min vs 60s vs 15s) ===")
    g_ds1_60 = make_clip_groups(g_ds1, s_ds1, 60)
    g_ds1_15 = make_clip_groups(g_ds1, s_ds1, 15)
    F_v21_60 = features_v2.build_features(X_ds1, rr_ds1, g_ds1_60)
    F_v21_15 = features_v2.build_features(X_ds1, rr_ds1, g_ds1_15)
    F_v3_60 = features_v3.build_features_v3(X_ds1, rr_ds1, g_ds1_60)
    F_v3_15 = features_v3.build_features_v3(X_ds1, rr_ds1, g_ds1_15)

    eligible_v3 = sorted(
        [c for c in candidate_results if c["features"] == "v3" and c["json_mb"] <= 3.0 and c["oof_metrics"]["per_class"]["N"]["f1"] >= 0.94],
        key=lambda r: r["oof_metrics"]["macro_f1_nsv"],
        reverse=True,
    )
    short_clip_candidates = ["v2.1_baseline_rf"] + [c["name"] for c in eligible_v3[:4]]
    short_clip_results = {}
    res_by_name = {c["name"]: c for c in candidate_results}

    for name in short_clip_candidates:
        spec = spec_by_name[name]
        w = np.asarray(res_by_name[name]["weights"], dtype=float)
        F_60 = F_v21_60 if spec["features"] == "v2.1" else F_v3_60
        F_15 = F_v21_15 if spec["features"] == "v2.1" else F_v3_15

        oof_60 = np.zeros((len(y_ds1), 4), dtype=np.float64)
        oof_15 = np.zeros((len(y_ds1), 4), dtype=np.float64)
        for (_, va), m in zip(folds, fold_models_by_name[name]):
            oof_60[va] = predict_proba_4class(m, F_60[va])
            oof_15[va] = predict_proba_4class(m, F_15[va])

        m30 = res_by_name[name]["oof_metrics"]
        m60 = compute_metrics(y_ds1, (oof_60 * w).argmax(1))
        m15 = compute_metrics(y_ds1, (oof_15 * w).argmax(1))
        short_clip_results[name] = {
            "30min": m30,
            "60s": m60,
            "15s": m15,
            "drop_60s": round(m30["macro_f1_nsv"] - m60["macro_f1_nsv"], 4),
            "drop_15s": round(m30["macro_f1_nsv"] - m15["macro_f1_nsv"], 4),
        }
        print(
            f"  {name:24s} | 30m={m30['macro_f1_nsv']:.3f} (S={m30['per_class']['S']['f1']:.3f}) | "
            f"60s={m60['macro_f1_nsv']:.3f} (S={m60['per_class']['S']['f1']:.3f}, Δ={m60['macro_f1_nsv']-m30['macro_f1_nsv']:+.3f}) | "
            f"15s={m15['macro_f1_nsv']:.3f} (S={m15['per_class']['S']['f1']:.3f}, Δ={m15['macro_f1_nsv']-m30['macro_f1_nsv']:+.3f})"
        )

    # 5) Freeze single winner strictly from DS1 CV
    if not eligible_v3:
        raise RuntimeError("GATE_FAILED: no v3 candidate satisfied JSON <= 3.0 MB and N F1 >= 0.94 on DS1 CV")

    winner_meta = eligible_v3[0]
    winner_name = winner_meta["name"]
    baseline_meta = res_by_name["v2.1_baseline_rf"]

    # Gate checks before unlocking DS2!
    assert winner_meta["oof_metrics"]["macro_f1_nsv"] > baseline_meta["oof_metrics"]["macro_f1_nsv"], (
        f"GATE_FAILED: winner {winner_name} did not beat v2.1 on DS1 CV"
    )
    assert winner_meta["parity_max_diff"] < 1e-4, (
        f"GATE_FAILED: winner {winner_name} JSON parity diff {winner_meta['parity_max_diff']}"
    )
    assert short_clip_results[winner_name]["drop_60s"] <= 0.04, (
        f"GATE_FAILED: winner {winner_name} 60s drop {short_clip_results[winner_name]['drop_60s']} > 0.04"
    )

    print(f"\n=== FROZEN WINNER SELECTED ON DS1 CV: {winner_name} ===")
    print(f"  DS1 OOF Macro F1 (N,S,V): {winner_meta['oof_metrics']['macro_f1_nsv']:.3f} "
          f"(vs v2.1 {baseline_meta['oof_metrics']['macro_f1_nsv']:.3f})")
    print(f"  Frozen DS1 OOF weights:   {winner_meta['weights']}")
    print(f"  Compact JSON size:        {winner_meta['json_mb']:.3f} MB ({winner_meta['json_bytes']} bytes)")

    # Fit winning v3 model ONCE on all 22 DS1 patients.
    winner_spec = spec_by_name[winner_name]
    winner_weights = np.asarray(winner_meta["weights"], dtype=float)
    winner_model = fit_candidate(winner_spec, F_v3_ds1, y_ds1)
    winner_json = export_model_json(winner_model, winner_spec["kind"], winner_weights)

    # -----------------------------------------------------------------------
    # Phase B: ONE-SHOT evaluation on locked DS2
    # -----------------------------------------------------------------------
    print("\n=== ONE-SHOT FINAL EVALUATION ON LOCKED DS2 ===")
    v21_bundle = joblib.load(os.path.join(ROOT, "models", "ecg_rf_small.joblib"))
    v21_weights = np.asarray(v21_bundle["decision_weights"], dtype=float)

    F_v21_ds2 = features_v2.build_features(X_ds2, rr_ds2, g_ds2)
    F_v3_ds2 = features_v3.build_features_v3(X_ds2, rr_ds2, g_ds2)

    p_v21_ds2 = predict_proba_4class(v21_bundle["model"], F_v21_ds2)
    pred_v21_aligned = (p_v21_ds2 * v21_weights).argmax(1)
    m_v21_aligned = compute_metrics(y_ds2, pred_v21_aligned)

    p_v3_ds2 = predict_proba_4class(winner_model, F_v3_ds2)
    pred_v3_aligned = (p_v3_ds2 * winner_weights).argmax(1)
    m_v3_aligned = compute_metrics(y_ds2, pred_v3_aligned)
    ds2_rec232_breakdown = compute_ds2_rec232_breakdown(y_ds2, g_ds2, pred_v21_aligned, pred_v3_aligned)

    # Also verify exact portable JSON prediction matches sklearn on DS2 probe
    ds2_probe_loop = np.asarray([json_predict_proba(winner_json, row) for row in F_v3_ds2[:300]])
    assert np.max(np.abs(p_v3_ds2[:300] - ds2_probe_loop)) < 1e-5

    print("--- Annotation-Aligned DS2 (49,661 beats) ---")
    for label, m in [("v2.1 (shipped RF)", m_v21_aligned), (f"v3 ({winner_name})", m_v3_aligned)]:
        pc = m["per_class"]
        print(
            f"  {label:28s} | N={pc['N']['f1']:.3f} S={pc['S']['f1']:.3f} (P={pc['S']['precision']:.3f}, R={pc['S']['recall']:.3f}) "
            f"V={pc['V']['f1']:.3f} | Macro(NSV)={m['macro_f1_nsv']:.3f} | Acc={m['accuracy']:.3f}"
        )

    print("\n--- End-to-End DS2 from Raw Signal (Pan-Tompkins portable) ---")
    m_v21_e2e = evaluate_end_to_end(DS2, v21_bundle["model"], v21_weights, "v2.1", sos_main, sos_det, use_fast_filter=True)
    m_v3_e2e = evaluate_end_to_end(DS2, winner_model, winner_weights, "v3", sos_main, sos_det, use_fast_filter=True)
    for label, m in [("v2.1 end-to-end", m_v21_e2e), (f"v3 end-to-end ({winner_name})", m_v3_e2e)]:
        pc = m["per_class"]
        print(
            f"  {label:32s} | det_sens={m['sensitivity']:.4f} ppv={m['positive_predictivity']:.4f} | "
            f"N={pc['N']['f1']:.3f} S={pc['S']['f1']:.3f} (P={pc['S']['precision']:.3f}, R={pc['S']['recall']:.3f}) "
            f"V={pc['V']['f1']:.3f} | Macro(NSV)={m['macro_f1_nsv']:.3f} | Acc={m['accuracy']:.3f} | {m['total_seconds']}s"
        )

    # -----------------------------------------------------------------------
    # Live scale-invariance test on app/samples/record_200.csv
    # -----------------------------------------------------------------------
    print("\n=== Live Scale-Invariance Test on app/samples/record_200.csv (0.001x / 1x / 1000x) ===")
    scale_results = {"v2.1": {}, "v3": {}}
    feats_v3_by_scale = {}
    proba_v3_by_scale = {}
    preds_v3_by_scale = {}
    peaks_by_scale = {}

    for tag, factor in [("0.001x_V", 0.001), ("1x_mV", 1.0), ("1000x_uV", 1000.0)]:
        sig_s = portable.sanitize_signal(sig_200 * factor, FS)
        sig_s = portable.to_360hz(sig_s, FS)
        sig_f = portable.filtfilt(sos_main, sig_s)
        peaks = portable.detect_rpeaks(sig_f, sos_det)
        beats, rr = [], []
        for k in range(1, len(peaks) - 1):
            p = int(peaks[k])
            if p - PRE < 0 or p + POST > len(sig_f):
                continue
            beats.append(sig_f[p - PRE:p + POST])
            rr.append([int(peaks[k] - peaks[k - 1]), int(peaks[k + 1] - peaks[k])])
        beats_arr = np.asarray(beats, dtype=float)
        rr_arr = np.asarray(rr, dtype=float)

        F21 = features_v2.build_features(beats_arr, rr_arr, np.zeros(len(beats_arr), dtype=int))
        p21 = predict_proba_4class(v21_bundle["model"], F21)
        pred21 = (p21 * v21_weights).argmax(1)
        scale_results["v2.1"][tag] = {
            "beats": int(len(peaks) - 2),
            "counts": {CLASSES[c]: int((pred21 == c).sum()) for c in range(4)},
        }

        F3 = features_v3.extract_recording_features_v3(beats_arr, rr_arr)
        p3 = np.asarray([json_predict_proba(winner_json, row) for row in F3])
        pred3 = (p3 * winner_weights).argmax(1)
        feats_v3_by_scale[tag] = F3
        proba_v3_by_scale[tag] = p3
        preds_v3_by_scale[tag] = pred3
        peaks_by_scale[tag] = peaks
        scale_results["v3"][tag] = {
            "beats": int(len(beats_arr)),
            "counts": {CLASSES[c]: int((pred3 == c).sum()) for c in range(4)},
        }

    max_feat_diff_v = float(np.max(np.abs(feats_v3_by_scale["1x_mV"] - feats_v3_by_scale["0.001x_V"])))
    max_feat_diff_uv = float(np.max(np.abs(feats_v3_by_scale["1x_mV"] - feats_v3_by_scale["1000x_uV"])))
    max_prob_diff_v = float(np.max(np.abs(proba_v3_by_scale["1x_mV"] - proba_v3_by_scale["0.001x_V"])))
    max_prob_diff_uv = float(np.max(np.abs(proba_v3_by_scale["1x_mV"] - proba_v3_by_scale["1000x_uV"])))
    labels_match_v = bool(np.array_equal(preds_v3_by_scale["1x_mV"], preds_v3_by_scale["0.001x_V"]))
    labels_match_uv = bool(np.array_equal(preds_v3_by_scale["1x_mV"], preds_v3_by_scale["1000x_uV"]))
    scale_results["v3_diffs"] = {
        "max_feature_diff_0.001x": max_feat_diff_v,
        "max_feature_diff_1000x": max_feat_diff_uv,
        "max_proba_diff_0.001x": max_prob_diff_v,
        "max_proba_diff_1000x": max_prob_diff_uv,
        "exact_label_match_0.001x": labels_match_v,
        "exact_label_match_1000x": labels_match_uv,
    }
    print("  v2.1 counts across scales:", scale_results["v2.1"])
    print("  v3   counts across scales:", scale_results["v3"])
    print(f"  v3 max feature diff: 0.001x={max_feat_diff_v:.2e}, 1000x={max_feat_diff_uv:.2e}")
    print(f"  v3 max proba diff:   0.001x={max_prob_diff_v:.2e}, 1000x={max_prob_diff_uv:.2e}, labels_match={labels_match_v and labels_match_uv}")

    detector_proto = run_detector_prototype_benchmark(sig_200, sos_main, sos_det)

    # -----------------------------------------------------------------------
    # Optional SVDB external evaluation
    # -----------------------------------------------------------------------
    if args.skip_svdb:
        svdb_res = {"status": "skipped", "reason": "skipped via --skip-svdb"}
    else:
        print("\n=== Optional External Validation on PhysioNet SVDB ===")
        svdb_res = evaluate_svdb_external(v21_bundle, winner_model, winner_weights, sos_main, limit=args.svdb_limit)
        print("  SVDB:", svdb_res if svdb_res["status"] != "completed" else {
            "records": svdb_res["records"],
            "beats": svdb_res["beats"],
            "counts": svdb_res["class_counts"],
            "v2.1_macro_nsv": round(svdb_res["v2.1"]["macro_f1_nsv"], 3),
            "v2.1_s_f1": round(svdb_res["v2.1"]["per_class"]["S"]["f1"], 3),
            "v3_macro_nsv": round(svdb_res["v3"]["macro_f1_nsv"], 3),
            "v3_s_f1": round(svdb_res["v3"]["per_class"]["S"]["f1"], 3),
        })

    # Save lightweight JSON summary
    summary = {
        "split": {
            "DS1": DS1,
            "DS2": DS2,
            "excluded_paced": list(PACED_RECORDS),
            "DS1_beats": int(len(y_ds1)),
            "DS2_beats": int(len(y_ds2)),
            "DS1_counts": {CLASSES[c]: int((y_ds1 == c).sum()) for c in range(4)},
            "DS2_counts": {CLASSES[c]: int((y_ds2 == c).sum()) for c in range(4)},
            "folds": fold_summary,
        },
        "class_f_ds1_proof": f_check_results,
        "ablation_ds1": ablation_results,
        "candidates_ds1": candidate_results,
        "short_clip_ds1": short_clip_results,
        "winner": {
            "name": winner_name,
            "weights": winner_meta["weights"],
            "json_bytes": winner_meta["json_bytes"],
            "json_mb": winner_meta["json_mb"],
            "parity_max_diff": winner_meta["parity_max_diff"],
            "loop_ms_per_1k": winner_meta["loop_ms_per_1k"],
        },
        "ds2_final": {
            "annotation_aligned": {"v2.1": m_v21_aligned, "v3": m_v3_aligned},
            "end_to_end": {"v2.1": m_v21_e2e, "v3": m_v3_e2e},
        },
        "ds2_rec232_breakdown": ds2_rec232_breakdown,
        "scale_invariance_record_200": scale_results,
        "detector_0.2x_prototype": detector_proto,
        "svdb_external": svdb_res,
        "total_runtime_seconds": round(time.perf_counter() - t_start, 2),
    }

    with open(args.json_out, "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=1)
    print(f"\nWrote {args.json_out} ({os.path.getsize(args.json_out)} bytes) in {summary['total_runtime_seconds']}s")


if __name__ == "__main__":
    main()
