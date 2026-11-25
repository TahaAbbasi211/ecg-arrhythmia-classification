"""End-to-end evaluation of the inference pipeline on the 22 DS2 test patients.

Reproduces notebook 08 (`08_portable_pipeline.ipynb`): every DS2 recording is read
from `data/mitdb`, the pipeline is run on the raw MLII lead and the detected beats
are matched against the expert annotations (within 0.1 s).

Usage:
    python scripts/evaluate_ds2.py                    # portable detector + forest
    python scripts/evaluate_ds2.py --scipy            # scipy + wfdb XQRS reference
    python scripts/evaluate_ds2.py --json out.json    # also write machine-readable results
"""
import argparse
import json
import os
import sys
import time

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from sklearn.metrics import classification_report, f1_score, precision_recall_fscore_support  # noqa: E402

from src.pipeline import AAMI_MAP, CLASSES, analyze, analyze_portable, load_model  # noqa: E402

DATA_DIR = os.path.join(ROOT, "data", "mitdb")
DS2 = [100, 103, 105, 111, 113, 117, 121, 123, 200, 202, 210,
       212, 213, 214, 219, 221, 222, 228, 231, 232, 233, 234]


def evaluate(fn, bundle, records=DS2, tolerance=36):
    """Run `fn` on every record and compare with the annotations."""
    import wfdb

    y_true, y_pred, offsets = [], [], []
    n_ann = n_det = n_tp = 0
    per_record = {}

    for rec in records:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec)))
        ann = wfdb.rdann(os.path.join(DATA_DIR, str(rec)), "atr")
        ch = record.sig_name.index("MLII")
        t0 = time.time()
        res = fn(record.p_signal[:, ch], record.fs, bundle)
        elapsed = time.time() - t0

        keep = [i for i, s in enumerate(ann.symbol) if s in AAMI_MAP]
        a_samples = ann.sample[keep]
        a_labels = [AAMI_MAP[ann.symbol[i]] for i in keep]

        n_ann += len(a_samples)
        n_det += len(res["peaks"])
        rec_tp = 0
        for p, c in zip(res["peaks"], res["pred"]):
            j = int(np.argmin(np.abs(a_samples - p)))
            if abs(a_samples[j] - p) <= tolerance:
                n_tp += 1
                rec_tp += 1
                offsets.append(int(a_samples[j] - p))
                if a_labels[j] in CLASSES:
                    y_true.append(CLASSES.index(a_labels[j]))
                    y_pred.append(int(c))
        per_record[int(rec)] = {
            "annotated": int(len(a_samples)),
            "detected": int(len(res["peaks"])),
            "matched": int(rec_tp),
            "seconds": round(elapsed, 2),
        }

    precision, recall, f1, support = precision_recall_fscore_support(
        y_true, y_pred, labels=[0, 1, 2, 3], zero_division=0)
    macro = float(f1_score(y_true, y_pred, labels=[0, 1, 2], average="macro"))
    return {
        "annotated": n_ann,
        "detected": n_det,
        "matched": n_tp,
        "sensitivity": n_tp / n_ann,
        "positive_predictivity": n_tp / n_det,
        "offset_percentiles_5_50_95": [float(v) for v in np.percentile(offsets, [5, 50, 95])],
        "macro_f1": macro,
        "per_class": {
            CLASSES[c]: {
                "precision": float(precision[c]),
                "recall": float(recall[c]),
                "f1": float(f1[c]),
                "support": int(support[c]),
            }
            for c in range(4)
        },
        "per_record": per_record,
        "y_true": y_true,
        "y_pred": y_pred,
    }


def report(result, name):
    print("=" * 24, name)
    print("annotated:", result["annotated"], "| detected:", result["detected"],
          "| matched:", result["matched"])
    print("sensitivity:", round(result["sensitivity"], 4),
          "| positive predictivity:", round(result["positive_predictivity"], 4))
    print("offset percentiles 5/50/95:", result["offset_percentiles_5_50_95"])
    print(classification_report(result["y_true"], result["y_pred"], labels=[0, 1, 2, 3],
                                target_names=CLASSES, digits=3, zero_division=0))
    print("macro F1 (N,S,V):", round(result["macro_f1"], 3))
    slowest = sorted(result["per_record"].items(), key=lambda kv: -kv[1]["seconds"])[:3]
    print("slowest records:", [(r, v["seconds"]) for r, v in slowest])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--scipy", action="store_true",
                    help="evaluate the scipy + wfdb XQRS reference instead of the portable pipeline")
    ap.add_argument("--json", help="write the results to this JSON file")
    ap.add_argument("--records", nargs="*", type=int, default=DS2)
    args = ap.parse_args()

    bundle = load_model(os.path.join(ROOT, "models", "ecg_rf_small.joblib"))
    fn = analyze if args.scipy else analyze_portable
    name = "scipy + XQRS reference" if args.scipy else "portable pipeline (Pan-Tompkins + 50-tree forest)"
    result = evaluate(fn, bundle, args.records)
    report(result, name)

    if args.json:
        payload = {k: v for k, v in result.items() if k not in ("y_true", "y_pred")}
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=1)
        print("wrote", args.json)


if __name__ == "__main__":
    main()
