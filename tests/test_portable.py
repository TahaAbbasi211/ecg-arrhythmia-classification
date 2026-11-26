"""The portable DSP core: hygiene, resampling, R-peaks, golden vectors."""

import json
import os

import numpy as np
import pytest

from src import pipeline, portable


def _load(root, name):
    with open(os.path.join(root, "export", name), encoding="utf-8") as handle:
        return json.load(handle)


# --- input hygiene ----------------------------------------------------------


@pytest.mark.parametrize("fs", [0, -1, 0.0, float("nan"), float("inf"), "abc", None])
def test_bad_sample_rates_are_rejected(fs):
    with pytest.raises(portable.SignalError):
        portable.check_sample_rate(fs)


def test_an_exact_360hz_rate_is_left_alone():
    x = np.arange(100.0)
    assert np.array_equal(portable.to_360hz(x, 360), x)
    # A rounding error smaller than FS_EPS is still the target rate.
    assert np.array_equal(portable.to_360hz(x, 360.0 + 1e-7), x)


def test_empty_and_tiny_signals_are_rejected():
    with pytest.raises(portable.SignalError, match="too short"):
        portable.sanitize_signal([], 360)
    with pytest.raises(portable.SignalError, match="too short"):
        portable.sanitize_signal([0.0, 1.0, 2.0, 3.0], 360)


def test_scattered_nan_and_inf_are_interpolated():
    x = np.arange(1000, dtype=float)
    x[10] = np.nan
    x[500:503] = np.inf
    x[900] = -np.inf
    out = portable.sanitize_signal(x, 360)
    assert np.isfinite(out).all()
    assert out[10] == pytest.approx(10.0)
    assert out[501] == pytest.approx(501.0)
    assert out[900] == pytest.approx(900.0)


def test_more_than_five_percent_bad_is_rejected():
    x = np.zeros(1000)
    x[:60] = np.nan   # 6% of the file
    with pytest.raises(portable.SignalError, match="at most"):
        portable.sanitize_signal(x, 360)


def test_a_long_gap_is_rejected_even_when_the_total_is_small():
    x = np.zeros(36000)
    x[1000:1300] = np.nan   # 0.83 s, under 1% of the file
    with pytest.raises(portable.SignalError, match="gap"):
        portable.sanitize_signal(x, 360)


# --- resampling -------------------------------------------------------------


def test_downsampling_matches_the_shared_dart_fixture(parity):
    assert parity["target"] == portable.TARGET_FS
    for case in parity["cases"]:
        raw = np.asarray(case["raw"], dtype=float)
        expected = np.asarray(case["expected"], dtype=float)
        got = portable.to_360hz(raw, case["fs"])
        assert got.shape == expected.shape
        assert np.allclose(got, expected, atol=1e-8, rtol=0)


def test_anti_alias_filter_keeps_the_ecg_band_and_kills_aliases():
    fs = 500
    t = np.arange(fs * 4) / fs
    ecg = np.sin(2 * np.pi * 20.0 * t)
    assert np.max(np.abs(portable.to_360hz(ecg, fs))) > 0.9

    # 250 Hz would fold to 110 Hz without the 150 Hz low-pass; order 3 leaves ~0.21.
    noise = np.sin(2 * np.pi * 250.0 * t)
    assert np.max(np.abs(portable.to_360hz(noise, fs))) < 0.3


def test_resample_linear_refuses_an_unknown_rate_change():
    with pytest.raises(portable.SignalError):
        portable.to_360hz(np.zeros(10), 0)


# --- R-peaks ----------------------------------------------------------------


def test_a_50mv_spike_does_not_hide_the_beats(record_200, bundle):
    spiked = record_200.copy()
    spiked[100] += 50.0
    out = pipeline.analyze_portable(spiked, 360, bundle)
    assert len(out["peaks"]) >= 75


# --- golden vectors ---------------------------------------------------------


def test_golden_vectors_match_the_reference_pipeline(root, vectors):
    cfg = _load(root, "ecg_config.json")
    forest = _load(root, "ecg_forest.json")
    assert vectors["notes"]["fs"] == portable.TARGET_FS

    for name, case in vectors["cases"].items():
        raw = np.asarray(case["raw"], dtype=float)
        out = portable.analyze_reference(raw, 360, cfg, forest)

        filtered = np.asarray(case["filtered"], dtype=float)
        assert out["signal"].shape == filtered.shape, name
        assert np.allclose(out["signal"], filtered, atol=1e-9, rtol=0), name
        assert list(out["peaks"]) == case["used_peaks"], name
        assert list(out["pred"]) == case["pred"], name
        proba = np.asarray(case["proba"], dtype=float)
        assert out["proba"].shape == proba.shape, name
        # The fixture stores probabilities at 7 decimals.
        assert np.allclose(out["proba"], proba, atol=1e-6, rtol=0), name

        # The detector on the filtered signal is its own golden value.
        sos_det = np.asarray(cfg["sos_det"], dtype=float)
        assert list(portable.detect_rpeaks(filtered, sos_det)) == case["detected_peaks"], name


def test_analyze_portable_agrees_with_the_reference(root, vectors, bundle):
    case = vectors["cases"]["record_100_60s"]
    raw = np.asarray(case["raw"], dtype=float)
    out = pipeline.analyze_portable(raw, 360, bundle)
    assert list(out["peaks"]) == case["used_peaks"]
    assert list(out["pred"]) == case["pred"]


def test_forest_predict_proba_rejects_non_finite_features(root):
    forest = _load(root, "ecg_forest.json")
    features = [0.0] * 57
    assert portable.forest_predict_proba(forest, features).shape == (4,)

    for bad in (float("nan"), float("inf")):
        features = [0.0] * 57
        features[7] = bad
        with pytest.raises(ValueError, match="finite"):
            portable.forest_predict_proba(forest, features)


def test_500hz_record_200_preserves_all_81_beats_and_predictions(root, bundle):
    from app.signal_io import read_signal_frame

    path = os.path.join(root, "app", "samples", "record_200.csv")
    with open(path, encoding="utf-8-sig") as handle:
        sig_360 = read_signal_frame(handle.read())["MLII_mV"].to_numpy(dtype=float)

    sig_500 = portable.resample_linear(sig_360, 360, target=500)
    out_360 = pipeline.analyze_portable(sig_360, 360, bundle)
    out_500 = pipeline.analyze_portable(sig_500, 500, bundle)

    assert len(out_360["peaks"]) == 81
    assert len(out_500["peaks"]) == 81
    assert [int((out_500["pred"] == c).sum()) for c in range(3)] == [37, 0, 44]
    assert np.array_equal(out_500["pred"], out_360["pred"])


def test_filtfilt_and_detect_rpeaks_handle_empty_and_tiny_inputs(root):
    cfg = _load(root, "ecg_config.json")
    sos_main = np.asarray(cfg["sos_main"], dtype=float)
    sos_det = np.asarray(cfg["sos_det"], dtype=float)

    empty = portable.filtfilt(sos_main, [])
    assert empty.shape == (0,)
    assert empty.dtype == float

    short = portable.detect_rpeaks(np.zeros(3), sos_det)
    assert short.shape == (0,)
    assert short.dtype == int
