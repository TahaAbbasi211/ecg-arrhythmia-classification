"""Pipeline glue: lazy wfdb, model loading and the decision weights."""

import os
import subprocess
import sys

import numpy as np
import pytest

from app.signal_io import heart_rate_bpm
from src import pipeline


def test_the_pipeline_module_imports_without_wfdb(root):
    code = "import sys; sys.modules['wfdb'] = None; import src.pipeline; print('ok')"
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

    # The reference detector still needs wfdb, and says so clearly.
    with pytest.raises(ImportError):
        pipeline.analyze(raw, 360, bundle)


def test_load_model_defaults_to_the_small_forest(root):
    assert pipeline.DEFAULT_MODEL == os.path.join("models", "ecg_rf_small.joblib")
    bundle = pipeline.load_model()
    assert "model" in bundle
    assert bundle["model"].n_estimators == 50
    # Every feature the model needs is produced by the beat feature code.
    assert bundle["model"].n_features_in_ == 57


def test_the_model_uses_the_documented_decision_weights(bundle):
    weights = np.asarray(
        bundle.get("decision_weights", bundle.get("weights", pipeline.DECISION_WEIGHTS)),
        dtype=float,
    )
    assert np.allclose(weights, np.array([1.0, 2.0, 1.0, 0.0]))
    # The fallback has to agree with the shipped model, or a pickle without
    # weights would classify differently.
    assert np.allclose(weights, pipeline.DECISION_WEIGHTS)


def test_classify_accepts_either_weights_key(vectors, bundle):
    case = vectors["cases"]["record_200_100s"]
    sig_f = np.asarray(case["filtered"], dtype=float)
    # _classify itself drops the first and the last beat, so give it every peak
    # the detector found rather than the golden interior list.
    peaks = np.asarray(case["detected_peaks"], dtype=int)
    expected = list(case["pred"])

    real = pipeline._classify(sig_f, peaks, bundle)
    assert list(real["peaks"]) == case["used_peaks"]
    assert list(real["pred"]) == expected

    # A bundle pickled with the other key name must classify the same way.
    alt = {"model": bundle["model"], "weights": pipeline.DECISION_WEIGHTS}
    assert list(pipeline._classify(sig_f, peaks, alt)["pred"]) == expected

    # And a bundle with no weights at all falls back to the default vector.
    plain = {"model": bundle["model"]}
    assert list(pipeline._classify(sig_f, peaks, plain)["pred"]) == expected


def test_too_few_beats_yield_an_empty_but_valid_result(vectors, bundle):
    case = vectors["cases"]["record_200_100s"]
    sig_f = np.asarray(case["filtered"], dtype=float)
    out = pipeline._classify(sig_f, np.array([1000, 1400]), bundle)
    assert out["pred"].size == 0
    assert out["proba"].shape == (0, 4)


def test_heart_rate_never_formats_as_nan():
    bpm = heart_rate_bpm(np.array([120, 480, 840]), 360)
    assert bpm == pytest.approx(60.0)
    assert "nan" not in ("%.0f" % bpm).lower()
