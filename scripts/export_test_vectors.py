"""Regenerate export/test_vectors.json, the golden vectors used by the Dart tests.

Mirrors notebook 10: for each (record, start, duration) segment the rounded MLII
lead is pushed through both the scikit-learn path (analyze_portable) and the
portable path (portable.analyze_reference); the run stops if they disagree.

Usage:
    python scripts/export_test_vectors.py [--check]
"""

import argparse
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from src import portable  # noqa: E402
from src.pipeline import analyze_portable, load_model  # noqa: E402

DATA_DIR = os.path.join(ROOT, "data", "mitdb")
EXPORT_DIR = os.path.join(ROOT, "export")
OUT_PATH = os.path.join(EXPORT_DIR, "test_vectors.json")

CASES = [("200", 100, 30), ("100", 60, 20), ("233", 300, 30)]


def build_cases(bundle, cfg, forest):
    import wfdb

    cases = {}
    for rec, start_s, dur_s in CASES:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec)))
        sig = record.p_signal[:, record.sig_name.index("MLII")]
        seg = np.round(sig[start_s * 360:(start_s + dur_s) * 360], 4)   # rounded input

        a = analyze_portable(seg, 360, bundle)
        b = portable.analyze_reference(seg, 360, cfg, forest)
        if not (np.array_equal(a["peaks"], b["peaks"]) and np.array_equal(a["pred"], b["pred"])):
            raise SystemExit("record %s: the scipy and portable paths disagree" % rec)
        if not np.allclose(a["proba"], b["proba"], atol=1e-6):
            raise SystemExit("record %s: probabilities differ between the two paths" % rec)

        sig_f = b["signal"]
        all_peaks = portable.detect_rpeaks(sig_f, np.array(cfg["sos_det"]))
        pos = {int(p): k for k, p in enumerate(all_peaks)}
        prev_list = [int(p - all_peaks[pos[int(p)] - 1]) for p in b["peaks"]]
        med = float(np.median(prev_list))

        beats = []
        for p in b["peaks"][:12]:
            k = pos[int(p)]
            beat = np.round(sig_f[p - 90:p + 110], 9)
            prev_rr = int(all_peaks[k] - all_peaks[k - 1])
            next_rr = int(all_peaks[k + 1] - all_peaks[k])
            feats = portable.beat_features(beat, prev_rr, next_rr, med)
            beats.append({
                "beat": beat.tolist(),
                "prev_rr": prev_rr,
                "next_rr": next_rr,
                "median_rr": med,
                "features": feats.tolist(),
                "proba": np.round(portable.forest_predict_proba(forest, feats), 7).tolist(),
            })

        cases["record_%s_%ss" % (rec, start_s)] = {
            "raw": seg.tolist(),
            "filtered": np.round(sig_f, 9).tolist(),
            "detected_peaks": [int(p) for p in all_peaks],
            "used_peaks": [int(p) for p in b["peaks"]],
            "pred": [int(v) for v in b["pred"]],
            "proba": np.round(b["proba"], 7).tolist(),
            "beat_tests": beats,
        }
        print(rec, "| samples:", len(seg), "| beats:", len(b["peaks"]),
              "| classes N/S/V/F:", np.bincount(b["pred"], minlength=4).tolist())
    return cases


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="only verify that the vectors on disk still match")
    args = ap.parse_args()

    bundle = load_model(os.path.join(ROOT, "models", "ecg_rf_small.joblib"))
    with open(os.path.join(EXPORT_DIR, "ecg_config.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    with open(os.path.join(EXPORT_DIR, "ecg_forest.json"), encoding="utf-8") as f:
        forest = json.load(f)

    cases = build_cases(bundle, cfg, forest)
    payload = {
        "notes": {
            "fs": 360,
            "tolerances": {
                "filtered": 1e-6,
                "features": "abs(a-b) <= 1e-6 + 1e-6*abs(b)",
                "proba": 1e-5,
                "peaks_and_pred": "exact",
            },
            "classes": ["N", "S", "V", "F"],
            "decision_weights": cfg["decision_weights"],
        },
        "cases": cases,
    }

    if args.check:
        with open(OUT_PATH, encoding="utf-8") as f:
            current = json.load(f)
        same = json.dumps(current, sort_keys=True) == json.dumps(payload, sort_keys=True)
        print("test vectors on disk match the current pipeline:", same)
        raise SystemExit(0 if same else 1)

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"))
    print("test_vectors.json:", round(os.path.getsize(OUT_PATH) / 1e6, 2), "MB")


if __name__ == "__main__":
    main()
