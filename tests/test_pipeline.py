"""Pipeline glue: lazy wfdb/joblib, v3.1 JSON loading, and decision weights."""

import os
import subprocess
import sys

import numpy as np
import pytest

from app.signal_io import heart_rate_bpm
from src import pipeline


def test_the_pipeline_module_imports_and_loads_without_wfdb_or_sklearn(root):
    code = "\n".join([
        "import sys",
        "for mod in ('wfdb', 'sklearn', 'joblib'): sys.modules[mod] = None",
        "import src.pipeline as p",
        "b = p.load_model()",
        "assert b['kind'] == 'hgb' and b['feature_count'] == 84",
        "print('ok')",
    ])
    result = subprocess.run([sys.executable, "-c", code], cwd=root,
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "ok"


def test_analyze_portable_does_not_need_wfdb(monkeypatch, vectors, bundle):
    case = vectors["cases"]["record_233_300s"]
    raw = np.asarray(case["raw"], dtype=float)

    monkeypatch.setitem(sys.modules, "wfdb", None)
    out = pipeline.analyze_portable(raw, 360, bundle)
    assert len(out["peaks"]) == len(case["used_peaks"])
    assert out["scores"].shape == out["proba"].shape

    # The reference detector still needs wfdb, and says so clearly.
    with pytest.raises(ImportError):
        pipeline.analyze(raw, 360, bundle)


def test_load_model_defaults_to_v3_json_and_supports_legacy_joblib(root):
    assert pipeline.DEFAULT_MODEL == os.path.join("export", "ecg_model_v3.json")
    bundle = pipeline.load_model()
    assert bundle["schema_version"] == 3
    assert bundle["kind"] == "hgb"
    assert bundle["feature_count"] == 84
    assert bundle["classes"] == [0, 1, 2]

    legacy = pipeline.load_model(os.path.join("models", "ecg_rf_small.joblib"))
    assert "model" in legacy
    assert legacy["model"].n_estimators == 50
    assert legacy["model"].n_features_in_ == 57


def test_the_model_uses_the_documented_decision_weights(bundle):
    weights = np.asarray(
        bundle.get("decision_weights", bundle.get("weights", pipeline.DECISION_WEIGHTS)),
        dtype=float,
    )
    assert np.allclose(weights, np.array([1.0, 0.25, 0.5, 0.0]))
    assert np.allclose(weights, pipeline.DECISION_WEIGHTS)


def test_classify_accepts_either_weights_key(vectors, bundle, legacy_bundle):
    case = vectors["cases"]["record_200_100s"]
    sig_f = np.asarray(case["filtered"], dtype=float)
    peaks = np.asarray(case["detected_peaks"], dtype=int)
    expected = list(case["pred"])

    real = pipeline._classify(sig_f, peaks, bundle)
    assert list(real["peaks"]) == case["used_peaks"]
    assert list(real["pred"]) == expected
    assert np.allclose(real["scores"].sum(axis=1), 1.0, atol=1e-12)
    assert np.array_equal(real["scores"].argmax(1), real["pred"])

    alt = {"model": bundle["model"], "weights": pipeline.DECISION_WEIGHTS}
    assert list(pipeline._classify(sig_f, peaks, alt)["pred"]) == expected

    plain = {"model": bundle["model"]}
    assert list(pipeline._classify(sig_f, peaks, plain)["pred"]) == expected

    # Legacy 57-feature joblib bundle must remain functional.
    legacy_out = pipeline._classify(sig_f, peaks, legacy_bundle)
    assert list(legacy_out["peaks"]) == case["used_peaks"]
    assert legacy_out["proba"].shape == (len(expected), 4)
    assert legacy_out["scores"].shape == (len(expected), 4)


def test_too_few_beats_yield_an_empty_but_valid_result(vectors, bundle):
    case = vectors["cases"]["record_200_100s"]
    sig_f = np.asarray(case["filtered"], dtype=float)
    out = pipeline._classify(sig_f, np.array([1000, 1400]), bundle)
    assert out["pred"].size == 0
    assert out["proba"].shape == (0, 4)
    assert out["scores"].shape == (0, 4)


def test_heart_rate_never_formats_as_nan():
    bpm = heart_rate_bpm(np.array([120, 480, 840]), 360)
    assert bpm == pytest.approx(60.0)
    assert "nan" not in ("%.0f" % bpm).lower()
