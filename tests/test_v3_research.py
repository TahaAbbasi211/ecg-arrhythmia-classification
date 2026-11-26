"""Unit tests for Phase 1 v3 scale-invariant, template, and rhythm features."""

import json
import os
import subprocess
import sys

import numpy as np
import pytest

from src import features_v3, portable


def _extract_beats_from_raw(raw, cfg):
    sos_main = np.asarray(cfg["sos_main"], dtype=float)
    sos_det = np.asarray(cfg["sos_det"], dtype=float)
    sig = portable.to_360hz(portable.sanitize_signal(raw, 360), 360)
    sig_f = portable.filtfilt(sos_main, sig)
    peaks = portable.detect_rpeaks(sig_f, sos_det)

    beats, rr = [], []
    for k in range(1, len(peaks) - 1):
        p = int(peaks[k])
        if p - portable.PRE < 0 or p + portable.POST > len(sig_f):
            continue
        beats.append(sig_f[p - portable.PRE:p + portable.POST])
        rr.append([int(peaks[k] - peaks[k - 1]), int(peaks[k + 1] - peaks[k])])
    return np.asarray(beats, dtype=float), np.asarray(rr, dtype=float)


def _synthetic_beat(p_amp=0.15, qrs_amp=1.2, t_amp=0.25, qrs_width=5.0, p_center=42.0):
    idx = np.arange(features_v3.BEAT_LEN, dtype=float)
    p = p_amp * np.exp(-0.5 * ((idx - p_center) / 6.0) ** 2)
    qrs = qrs_amp * np.exp(-0.5 * ((idx - features_v3.R) / qrs_width) ** 2)
    t = t_amp * np.exp(-0.5 * ((idx - 148.0) / 14.0) ** 2)
    return p + qrs + t


def test_features_v3_schema_and_groups():
    assert len(features_v3.FEATURE_NAMES) == 84
    assert len(set(features_v3.FEATURE_NAMES)) == 84

    covered = []
    for name in ("rhythm", "morph", "template", "pt_wave"):
        sl = features_v3.FEATURE_GROUPS[name]
        covered.extend(range(*sl.indices(len(features_v3.FEATURE_NAMES))))
    assert covered == list(range(len(features_v3.FEATURE_NAMES)))


def test_features_v3_has_zero_scipy_dependency(root):
    code = (
        "import sys, numpy as np; "
        "sys.modules['scipy'] = None; "
        "from src.features_v3 import extract_recording_features_v3; "
        "F = extract_recording_features_v3(np.random.RandomState(0).randn(5, 200), "
        "np.full((5, 2), 280.0)); "
        "assert F.shape == (5, 84) and np.all(np.isfinite(F)); "
        "print('ok')"
    )
    res = subprocess.run([sys.executable, "-c", code], cwd=root, capture_output=True, text=True)
    assert res.returncode == 0, res.stderr
    assert res.stdout.strip() == "ok"


def test_features_v3_scale_invariance_across_volts_mv_uv(root, record_200):
    with open(os.path.join(root, "export", "ecg_config.json"), encoding="utf-8") as handle:
        cfg = json.load(handle)

    beats_1x, rr = _extract_beats_from_raw(record_200, cfg)
    beats_v, rr_v = _extract_beats_from_raw(record_200 * 0.001, cfg)
    beats_uv, rr_uv = _extract_beats_from_raw(record_200 * 1000.0, cfg)

    assert np.array_equal(rr, rr_v)
    assert np.array_equal(rr, rr_uv)

    f_1x = features_v3.extract_recording_features_v3(beats_1x, rr)
    f_v = features_v3.extract_recording_features_v3(beats_v, rr_v)
    f_uv = features_v3.extract_recording_features_v3(beats_uv, rr_uv)

    assert f_1x.shape == (len(beats_1x), 84)
    assert np.max(np.abs(f_1x - f_v)) < 1e-9
    assert np.max(np.abs(f_1x - f_uv)) < 1e-9

    # Also verify grouped extraction across mixed-scale recordings.
    n1 = len(beats_1x) // 2
    X_mix = np.vstack([beats_v[:n1], beats_uv[n1:]])
    X_1x = np.vstack([beats_1x[:n1], beats_1x[n1:]])
    g = np.concatenate([np.full(n1, 1), np.full(len(beats_1x) - n1, 2)])
    f_grp_1x = features_v3.build_features_v3(X_1x, rr, g)
    f_grp_mix = features_v3.build_features_v3(X_mix, rr, g)
    assert np.max(np.abs(f_grp_1x - f_grp_mix)) < 1e-9


@pytest.mark.parametrize("n_beats", [0, 1, 2, 3])
def test_features_v3_tiny_and_empty_clips_are_finite(n_beats):
    rng = np.random.RandomState(42)
    beats = rng.randn(n_beats, 200) if n_beats > 0 else np.zeros((0, 200))
    rr = np.full((n_beats, 2), 270.0) if n_beats > 0 else np.zeros((0, 2))
    out = features_v3.extract_recording_features_v3(beats, rr)
    assert out.shape == (n_beats, 84)
    assert np.all(np.isfinite(out))


def test_features_v3_flat_beats_and_zero_rr_produce_no_nan_or_inf():
    zeros = np.zeros((5, 200), dtype=float)
    const = np.full((5, 200), 3.75, dtype=float)
    zero_rr = np.zeros((5, 2), dtype=float)

    for beats in (zeros, const):
        out = features_v3.extract_recording_features_v3(beats, zero_rr)
        assert out.shape == (5, 84)
        assert np.all(np.isfinite(out))


def test_compensatory_pause_ratio_calculation():
    assert features_v3.compute_compensatory_pause_ratio(300.0, 300.0, 300.0) == pytest.approx(1.0)
    # Incomplete pause typical of PAC (S): (210 + 330) / (2 * 300) = 0.90 < 1.0
    assert features_v3.compute_compensatory_pause_ratio(210.0, 330.0, 300.0) == pytest.approx(0.90)
    # Full compensatory pause typical of PVC (V): (210 + 390) / (2 * 300) = 1.00
    assert features_v3.compute_compensatory_pause_ratio(210.0, 390.0, 300.0) == pytest.approx(1.0)
    # Zero local_med_rr is guarded without ZeroDivisionError or NaN
    assert np.isfinite(features_v3.compute_compensatory_pause_ratio(100.0, 100.0, 0.0))

    beats = np.tile(_synthetic_beat(), (11, 1))
    rr = np.full((11, 2), 300.0)
    rr[4] = [210.0, 330.0]  # PAC
    rr[7] = [210.0, 390.0]  # PVC
    feat = features_v3.extract_recording_features_v3(beats, rr)
    idx_cpr = features_v3.FEATURE_INDEX["comp_pause_ratio"]
    assert feat[2, idx_cpr] == pytest.approx(1.0)
    assert feat[4, idx_cpr] == pytest.approx(0.90)
    assert feat[7, idx_cpr] == pytest.approx(1.0)


def test_recording_template_and_regional_p_qrs_t_features():
    normal = _synthetic_beat(p_amp=0.20, qrs_amp=1.20, t_amp=0.30, qrs_width=5.0)
    beat_s = _synthetic_beat(p_amp=-0.25, qrs_amp=1.20, t_amp=0.30, qrs_width=5.0, p_center=52.0)
    beat_v = _synthetic_beat(p_amp=0.0, qrs_amp=-1.60, t_amp=-0.35, qrs_width=14.0)

    beats = np.vstack([np.tile(normal, (8, 1)), beat_s[None, :], beat_v[None, :]])
    rr = np.full((10, 2), 280.0)

    _, x_rec = features_v3.compute_recording_scale(beats)
    tpl = features_v3.compute_recording_template(x_rec)
    # Median template across 8 normal + 2 abnormal beats matches the normal beat.
    assert np.allclose(tpl, x_rec[0], atol=1e-9)

    feat = features_v3.extract_recording_features_v3(beats, rr)
    i_corr_p = features_v3.FEATURE_INDEX["corr_p"]
    i_corr_qrs = features_v3.FEATURE_INDEX["corr_qrs"]
    i_rms_qrs = features_v3.FEATURE_INDEX["rms_diff_qrs"]
    i_qrs_m_p = features_v3.FEATURE_INDEX["corr_qrs_minus_p"]
    i_p_max_diff = features_v3.FEATURE_INDEX["p_max_diff_tpl"]

    # Normal beat matches template closely everywhere.
    assert feat[0, i_corr_p] > 0.99
    assert feat[0, i_corr_qrs] > 0.99
    assert feat[0, i_rms_qrs] < 1e-6

    # S beat keeps normal QRS correlation but drops P-wave correlation sharply.
    assert feat[8, i_corr_qrs] > 0.95
    assert feat[8, i_corr_p] < 0.0
    assert feat[8, i_qrs_m_p] > 0.95
    assert feat[8, i_p_max_diff] < -0.1

    # V beat has inverted/wide QRS -> low QRS correlation and high QRS RMS diff.
    assert feat[9, i_corr_qrs] < -0.5
    assert feat[9, i_rms_qrs] > feat[8, i_rms_qrs]
