"""Regenerate export/test_vectors.json, the golden vectors used by Python and Dart tests.

Runs the full v3.1 portable pipeline (`analyze_portable` and `portable.analyze_reference`)
on 3 MIT-BIH test segments and verifies scale invariance (0.001x, 1x, 1000x).

Usage:
    D:\\ANACONDA\\python.exe scripts/export_test_vectors.py [--check]
"""

import argparse
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from src import features_v3, portable  # noqa: E402
from src.pipeline import analyze_portable, load_model  # noqa: E402

DATA_DIR = os.path.join(ROOT, "data", "mitdb")
EXPORT_DIR = os.path.join(ROOT, "export")
OUT_PATH = os.path.join(EXPORT_DIR, "test_vectors.json")

CASES = [("200", 100, 30), ("100", 60, 20), ("233", 300, 30)]


def _select_feature_indices(pred, limit_head=12, limit_class=4):
    """Select key beat indices covering head, S/V arrhythmias, and tail."""
    n = len(pred)
    selected = set(range(min(limit_head, n)))
    for cls_id in (1, 2):
        matches = [int(i) for i, p in enumerate(pred) if int(p) == cls_id]
        selected.update(matches[:limit_class])
    if n > 0:
        selected.add(n - 1)
    return sorted(selected)


def build_cases(bundle, cfg, model):
    import wfdb

    cases = {}
    for rec, start_s, dur_s in CASES:
        record = wfdb.rdrecord(os.path.join(DATA_DIR, str(rec)))
        sig = record.p_signal[:, record.sig_name.index("MLII")]
        seg = np.round(sig[start_s * 360:(start_s + dur_s) * 360], 4)

        a = analyze_portable(seg, 360, bundle)
        b = portable.analyze_reference(seg, 360, cfg, model)
        if not (np.array_equal(a["peaks"], b["peaks"]) and np.array_equal(a["pred"], b["pred"])):
            raise SystemExit("record %s: pipeline and reference paths disagree" % rec)
        if not np.allclose(a["proba"], b["proba"], atol=1e-12, rtol=0):
            raise SystemExit("record %s: probabilities differ between paths" % rec)
        if not np.allclose(a["scores"], b["scores"], atol=1e-12, rtol=0):
            raise SystemExit("record %s: scores differ between paths" % rec)

        sig_f = b["signal"]
        all_peaks = portable.detect_rpeaks(sig_f, np.asarray(cfg["sos_det"], dtype=float))
        pos = {int(p): k for k, p in enumerate(all_peaks)}

        beats, rr = [], []
        for p in b["peaks"]:
            k = pos[int(p)]
            beats.append(sig_f[int(p) - 90:int(p) + 110])
            rr.append([int(all_peaks[k] - all_peaks[k - 1]), int(all_peaks[k + 1] - all_peaks[k])])
        feats_all = features_v3.extract_recording_features_v3(beats, rr, fs=360)

        sig_f_rounded = np.round(sig_f, 12)
        beats_rounded = [sig_f_rounded[int(p) - 90:int(p) + 110] for p in b["peaks"]]
        feats_rounded = features_v3.extract_recording_features_v3(beats_rounded, rr, fs=360)
        if np.max(np.abs(feats_all - feats_rounded)) >= 1e-10:
            raise SystemExit("record %s: filtered signal rounding drifted features >= 1e-10" % rec)

        feat_indices = _select_feature_indices(b["pred"])
        cases["record_%s_%ss" % (rec, start_s)] = {
            "raw": seg.tolist(),
            "filtered": sig_f_rounded.tolist(),
            "detected_peaks": [int(p) for p in all_peaks],
            "used_peaks": [int(p) for p in b["peaks"]],
            "pred": [int(v) for v in b["pred"]],
            "proba": np.round(b["proba"], 10).tolist(),
            "scores": np.round(b["scores"], 10).tolist(),
            "feature_indices": feat_indices,
            "features": [feats_all[idx].tolist() for idx in feat_indices],
            "feature_proba": [np.round(b["proba"][idx], 10).tolist() for idx in feat_indices],
            "feature_scores": [np.round(b["scores"][idx], 10).tolist() for idx in feat_indices],
        }
        print(rec, "| samples:", len(seg), "| beats:", len(b["peaks"]),
              "| key_feats:", len(feat_indices),
              "| classes N/S/V/F:", np.bincount(b["pred"], minlength=4).tolist())

    # Build scale-invariance verification case (Volts 0.001x, mV 1x, uV 1000x) on record_200_100s.
    base = cases["record_200_100s"]
    seg_1x = np.asarray(base["raw"], dtype=np.float64)
    ref_1x = portable.analyze_reference(seg_1x, 360, cfg, model)

    def _extract_feats(res_dict):
        sf = res_dict["signal"]
        pk_all = portable.detect_rpeaks(sf, np.asarray(cfg["sos_det"], dtype=float))
        pk_pos = {int(p): k for k, p in enumerate(pk_all)}
        bts, rrs = [], []
        for p in res_dict["peaks"]:
            k = pk_pos[int(p)]
            bts.append(sf[int(p) - 90:int(p) + 110])
            rrs.append([int(pk_all[k] - pk_all[k - 1]), int(pk_all[k + 1] - pk_all[k])])
        return features_v3.extract_recording_features_v3(bts, rrs, fs=360)

    feats_1x = _extract_feats(ref_1x)
    max_feat_diffs = {}
    max_proba_diffs = {}
    for scale_label, factor in [("0.001", 0.001), ("1.0", 1.0), ("1000.0", 1000.0)]:
        res_s = portable.analyze_reference(seg_1x * factor, 360, cfg, model)
        if not (np.array_equal(res_s["peaks"], ref_1x["peaks"]) and np.array_equal(res_s["pred"], ref_1x["pred"])):
            raise SystemExit("scale %s broke peak/pred invariance" % scale_label)
        feats_s = _extract_feats(res_s)
        f_diff = float(np.max(np.abs(feats_s - feats_1x)))
        p_diff = float(np.max(np.abs(res_s["proba"] - ref_1x["proba"])))
        s_diff = float(np.max(np.abs(res_s["scores"] - ref_1x["scores"])))
        if f_diff >= 1e-9 or p_diff >= 1e-6 or s_diff >= 1e-6:
            raise SystemExit("scale %s exceeded invariance tolerances: f=%.2e p=%.2e s=%.2e"
                             % (scale_label, f_diff, p_diff, s_diff))
        max_feat_diffs[scale_label] = f_diff
        max_proba_diffs[scale_label] = p_diff

    scale_case = {
        "base_case": "record_200_100s",
        "scales": [0.001, 1.0, 1000.0],
        "used_peaks": [int(p) for p in ref_1x["peaks"]],
        "pred": [int(v) for v in ref_1x["pred"]],
        "proba": np.round(ref_1x["proba"], 10).tolist(),
        "scores": np.round(ref_1x["scores"], 10).tolist(),
        "max_feature_diff_vs_1x": max_feat_diffs,
        "max_proba_diff_vs_1x": max_proba_diffs,
    }
    return cases, scale_case


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="only verify that the vectors on disk still match")
    args = ap.parse_args()

    bundle = load_model()
    with open(os.path.join(EXPORT_DIR, "ecg_config.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    with open(os.path.join(EXPORT_DIR, "ecg_model_v3.json"), encoding="utf-8") as f:
        model = json.load(f)

    cases, scale_case = build_cases(bundle, cfg, model)
    payload = {
        "notes": {
            "schema_version": 3,
            "model_file": "ecg_model_v3.json",
            "fs": 360,
            "feature_count": 84,
            "tolerances": {
                "filtered": 1e-6,
                "features": 1e-10,
                "proba": 1e-6,
                "scores": 1e-6,
                "peaks_and_pred": "exact",
            },
            "classes": ["N", "S", "V", "F"],
            "decision_weights": cfg["decision_weights"],
        },
        "cases": cases,
        "scale_invariance": scale_case,
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
