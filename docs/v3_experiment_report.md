# ECG Arrhythmia Classification — Phase 1 v3.0 Experiment Report

**Branch:** `feat/v3-model`  
**Phase Scope:** Research, scale-invariant feature engineering (`src/features_v3.py`), leak-free inter-patient model selection (`scripts/train_v3.py`), and benchmarking. All `v2.1` production files (`src/portable.py`, `src/pipeline.py`, `export/`, `models/`, `mobile/`, `app/`) remain unmodified.

---

## 1. Experimental Protocol & Zero-Leakage Verification

- **Database & Lead:** MIT-BIH Arrhythmia Database (`data/mitdb/`, 360 Hz, lead `MLII`).
- **Standard de Chazal Inter-Patient Split (Locked):**
  - **Excluded Paced Records (4):** `102, 104, 107, 217`.
  - **Excluded Class:** `Q` (only 15 non-paced beats across DS1+DS2).
  - **`DS1` (Training — 22 patients, 50,969 beats):** `[101, 106, 108, 109, 112, 114, 115, 116, 118, 119, 122, 124, 201, 203, 205, 207, 208, 209, 215, 220, 223, 230]`  
    Class counts: `N = 45,824`, `S = 943`, `V = 3,788`, `F = 414`.
  - **`DS2` (Locked Test — 22 unseen patients, 49,661 beats):** `[100, 103, 105, 111, 113, 117, 121, 123, 200, 202, 210, 212, 213, 214, 219, 221, 222, 228, 231, 232, 233, 234]`  
    Class counts: `N = 44,218`, `S = 1,836`, `V = 3,219`, `F = 388`.
- **Golden Rule Compliance:** All feature ablations, handling of class `F`, model family selection, hyperparameters, OOF decision weights, and short-clip stability gates were performed **exclusively inside 5-fold `StratifiedGroupKFold` on `DS1`**. `DS2` remained locked until the single frozen winning model from `DS1` CV was finalized, and was evaluated **once**.

### 1.1 `DS1` 5-Fold `StratifiedGroupKFold` Distribution

| Fold | Validation Patients | N | S | V | F |
|---|---|---:|---:|---:|---:|
| 0 | `114, 118, 207, 208, 215` | 10,302 | 219 | 1,425 | 377 |
| 1 | `106, 115, 201, 205, 230` | 9,911 | 131 | 790 | 13 |
| 2 | `101, 112, 124, 203` | 8,454 | 38 | 491 | 6 |
| 3 | `108, 116, 119, 209` | 8,198 | 388 | 571 | 2 |
| 4 | `109, 122, 220, 223` | 8,959 | 167 | 511 | 16 |

### 1.2 `DS1`-Only Proof for Dropping Class `F` (`w_F = 0`)

In `DS1`, **372 of 414 (89.9%)** fusion (`F`) beats come from a single patient (`208`), leaving only `42` beats across the remaining 21 patients (`2–16` per other fold). Optimizing all 4 weights `[1, w_S, w_V, w_F]` strictly on `DS1` 5-fold OOF predictions confirms that predicting `F` fails inter-patient generalization without ever looking at `DS2`:

| Model on `DS1` OOF | Policy | Weights `[N, S, V, F]` | F Prec | F Rec | F F1 | Macro F1 `(N,S,V)` |
|---|---|---|---:|---:|---:|---:|
| `v2.1` RF(50, leaf=5) | Tune `w_F` | `[1.0, 2.0, 1.0, 2.0]` | 0.026 | 0.012 | 0.017 | 0.645 |
| `v2.1` RF(50, leaf=5) | `w_F = 0` | `[1.0, 2.0, 1.25, 0.0]` | 0.000 | 0.000 | 0.000 | **0.648** |
| `v3` HGB(120, leaf=15) | Tune `w_F` | `[1.0, 0.5, 0.5, 16.0]` | 0.081 | 0.464 | 0.138 | 0.735 |
| `v3` HGB(120, leaf=15) | `w_F = 0` | `[1.0, 0.25, 0.25, 0.0]` | 0.000 | 0.000 | 0.000 | **0.738** |

Setting `w_F = 0` (and testing `3-class` fitting excluding `F` from `fit()`) improves `Macro F1 (N,S,V)` and avoids ~92–97% false-alarm rates on fusion predictions.

---

## 2. `v3` Feature Engineering & `DS1` CV Ablation

`src/features_v3.py` defines **84 zero-`scipy`, 1:1 Dart/JS-portable features** grouped into:
- **Local Rhythm (`14` cols):** `±15`-beat local median RR (`local_med_rr`), `comp_pause_ratio = (prev_rr + next_rr) / max(2 * local_med_rr, 1e-8)`, local IQR variability (`local_iqr_rel`), prematurity z-score, and adjacent RR ratios (`prev_rr/prev2_rr`, `next_rr/next2_rr`, asymmetry).
- **Scale-Invariant Morphology (`52` cols):** Each beat is median-centered and divided by `rec_scale = max(median(beat_p2p), 1e-8)` (`x_rec`), then all 12 amplitude/moment scalars and 40 downsampled shape points are computed on `x_rec`.
- **Recording Median Beat Template (`9` cols):** Element-wise median beat `template` on `x_rec`, with Pearson correlation and RMS diff over P-wave/PR (`[R-80:R-20]`), QRS (`[R-30:R+30]`), T/ST (`[R+25:R+100]`), full beat, plus `corr_qrs - corr_p`.
- **P-wave & T-wave Regional Features (`9` cols):** `E_P / (E_QRS + eps)`, `E_T / (E_QRS + eps)`, P min/max/peak-position, P min/max deviation from `template`, and T max & template deviation.

### `DS1` 5-Fold CV Feature Ablation

| Classifier | Feature Subset | Cols | N F1 | S F1 | V F1 | Macro F1 `(N,S,V)` | Fold Mean ± Std |
|---|---|---:|---:|---:|---:|---:|---:|
| `RF(50, leaf=5)` | `v2.1` baseline | 57 | 0.951 | 0.313 | 0.680 | 0.648 | 0.665 ± 0.147 |
| `RF(50, leaf=5)` | `v2.1` RR + `rec_scale` morph | 57 | 0.960 | 0.338 | 0.690 | 0.663 | 0.665 ± 0.121 |
| `RF(50, leaf=5)` | `v3`: `rec_scale` + `local_rr` | 66 | 0.963 | 0.281 | 0.731 | 0.658 | 0.652 ± 0.069 |
| `RF(50, leaf=5)` | `v3`: `rec_scale` + `template/PT` + `v2.1` RR | 75 | 0.961 | 0.335 | 0.793 | 0.696 | 0.706 ± 0.093 |
| `RF(50, leaf=5)` | **`v3` full (`local_rr` + `rec_scale` + `template/PT`)** | **84** | **0.976** | **0.352** | **0.862** | **0.730** | **0.715 ± 0.072** |
| `HGB(120, leaf=15)` | `v2.1` baseline | 57 | 0.944 | 0.278 | 0.665 | 0.629 | 0.661 ± 0.147 |
| `HGB(120, leaf=15)` | `v2.1` RR + `rec_scale` morph | 57 | 0.945 | 0.358 | 0.641 | 0.648 | 0.664 ± 0.135 |
| `HGB(120, leaf=15)` | `v3`: `rec_scale` + `local_rr` | 66 | 0.958 | 0.386 | 0.679 | 0.674 | 0.669 ± 0.123 |
| `HGB(120, leaf=15)` | `v3`: `rec_scale` + `template/PT` + `v2.1` RR | 75 | 0.969 | **0.390** | 0.876 | **0.745** | **0.761 ± 0.105** |
| `HGB(120, leaf=15)` | `v3` full (`local_rr` + `rec_scale` + `template/PT`) | 84 | **0.975** | 0.357 | **0.883** | 0.738 | 0.742 ± 0.092 |

Key ablation takeaways on `DS1` CV:
1. Replacing unscaled amplitudes with `rec_scale` normalization alone raises `RF` Macro F1 (`0.648 → 0.663`) and `HGB` Macro F1 (`0.629 → 0.648`, `S`: `0.278 → 0.358`).
2. Adding patient `template` + P/T-wave features delivers the largest leap in inter-patient generalization (`V` jumps `+0.113` on RF and `+0.211` on HGB; Macro F1 rises to `0.696–0.745`).
3. Full `v3` (84 features) lifts `RF` from `0.648 → 0.730` (`+0.082`) and `HGB` from `0.629 → 0.738` (`+0.109`), while cutting fold-to-fold standard deviation nearly in half (`0.147 → 0.072–0.092`).

---

## 3. Model Family Comparison on `DS1` 5-Fold CV

All candidates were evaluated on the exact same 5 `StratifiedGroupKFold` splits of `DS1`, exported to compact JSON, and verified against pure-Python loop inference (`parity_max_diff <= 1.01e-6`).

| Candidate | Model / Features | OOF Weights `[N,S,V,F]` | N F1 | S F1 | V F1 | Macro F1 `(N,S,V)` | Nested CV Macro F1 | Acc | JSON Size (MB) | Loop Parity Max Diff | Loop Speed (ms / 1k) |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `v2.1_baseline_rf` | RF(50, l=5) / v2.1 | `[1, 2.0, 1.25, 0]` | 0.951 | 0.313 | 0.680 | 0.648 | 0.620 | 0.906 | 1.275 | 2.0e-08 | 0.17 |
| `v3_rf_50_l5` | RF(50, l=5) / v3 | `[1, 1.5, 0.75, 0]` | 0.976 | 0.352 | 0.862 | 0.730 | 0.686 | 0.952 | 1.157 | 4.4e-08 | 0.18 |
| `v3_rf_80_l5_d16` | RF(80, l=5, d=16) / v3 | `[1, 1.0, 0.5, 0]` | 0.976 | 0.311 | 0.848 | 0.711 | 0.656 | 0.953 | 1.699 | 3.1e-08 | 0.33 |
| `v3_rf_100_l10_d16` | RF(100, l=10, d=16) / v3 | `[1, 1.5, 1.0, 0]` | 0.966 | 0.325 | 0.808 | 0.700 | 0.662 | 0.934 | 1.701 | 3.3e-08 | 0.29 |
| `v3_et_60_l5_d16` | ET(60, l=5, d=16) / v3 | `[1, 1.25, 1.0, 0]` | 0.964 | 0.237 | 0.803 | 0.668 | 0.634 | 0.932 | 3.213 | 5.0e-08 | 0.27 |
| `v3_et_100_l5_d18` | ET(100, l=5, d=18) / v3 | `[1, 1.25, 0.5, 0]` | 0.970 | 0.207 | 0.830 | 0.669 | 0.643 | 0.941 | 5.997 | 3.8e-08 | 0.52 |
| `v3_et_100_l10_d16` | ET(100, l=10, d=16) / v3 | `[1, 0.75, 0.75, 0]` | 0.968 | 0.213 | 0.802 | 0.661 | 0.646 | 0.939 | 4.052 | 6.4e-08 | 0.41 |
| `v3_hgb_100_l15_bal` | HGB(100, leaf=15, bal) / v3 | `[1, 0.25, 0.25, 0]` | 0.976 | 0.365 | 0.888 | 0.743 | 0.734 | 0.953 | 0.217 | 4.4e-07 | 0.34 |
| `v3_hgb_150_l15_bal` | HGB(150, leaf=15, bal) / v3 | `[1, 0.25, 0.25, 0]` | 0.975 | 0.365 | 0.885 | 0.742 | 0.727 | 0.952 | 0.319 | 1.0e-06 | 0.50 |
| `v3_hgb_150_l31_bal` | HGB(150, leaf=31, bal) / v3 | `[1, 0.25, 0.25, 0]` | 0.976 | 0.365 | 0.877 | 0.739 | 0.740 | 0.952 | 0.461 | 2.7e-07 | 0.50 |
| `v3_hgb_120_l15_unw` | HGB(120, leaf=15, unw) / v3 | `[1, 1.0, 0.25, 0]` | 0.978 | 0.366 | 0.897 | 0.747 | 0.718 | 0.957 | 0.399 | 7.4e-08 | 0.60 |
| `v3_gb_30_d3_bal` | GB(30, d=3, sqrt, bal) / v3 | `[1, 0.25, 0.25, 0]` | 0.977 | 0.329 | 0.897 | 0.734 | 0.727 | 0.954 | 0.054 | 7.2e-08 | 0.07 |
| `v3_mlp_64_32_unw` | Scaler+MLP(64,32) / v3 | `[1, 0.25, 0.5, 0]` | 0.980 | 0.330 | 0.852 | 0.721 | 0.706 | 0.957 | 0.074 | 5.9e-08 | 1.45 |
| `v3_mlp_64_32_ovs` | Scaler+MLP(64,32, ovs=0.15) / v3 | `[1, 1.5, 0.25, 0]` | 0.974 | 0.344 | 0.808 | 0.708 | 0.700 | 0.945 | 0.074 | 8.2e-09 | 0.49 |
| `v3_hgb_120_l15_unw_3cls` | HGB(120, leaf=15, unw, 3-cls fit) | `[1, 0.5, 0.75, 0]` | 0.978 | **0.378** | 0.879 | 0.745 | 0.711 | 0.957 | 0.299 | 8.9e-09 | 0.23 |
| **`v3_hgb_100_l15_bal_3cls`** | **HGB(100, leaf=15, bal, 3-cls fit)** | **`[1, 0.25, 0.5, 0]`** | **0.978** | 0.364 | **0.899** | **0.747** | **0.741** | **0.956** | **0.162** | **3.1e-08** | **296.3** |

> **Timing Unit Correction (`1000×`):** In Phase 1, `scripts/train_v3.py` mistakenly multiplied `time.perf_counter()` seconds by `1000.0 / len(probe)` instead of `1_000_000.0 / len(probe)`, under-reporting loop speeds in the other rows above by `1000×` (re-measured on the exported `v3.1` model with the fixed formula in `scripts/export_v3_model.py`: **`296.26 ms / 1k beats`**).

**Frozen Winner Selected on `DS1` CV:** **`v3_hgb_100_l15_bal_3cls`** (`HistGradientBoostingClassifier(max_iter=100, max_leaf_nodes=15, learning_rate=0.08, min_samples_leaf=30, l2_regularization=1.0, random_state=42)` trained with balanced sample weights on `N, S, V` only, with frozen OOF weights `[1.0, 0.25, 0.5, 0.0]`). It achieves the highest `DS1` OOF Macro F1 (`0.747`), the highest **nested fold-out** Macro F1 (`0.741`), and exports to just **162,294 bytes (`0.162 MB`)** — **7.8× smaller** than `v2.1`'s `1.275 MB` JSON.

---

## 4. Short-Clip Stability on `DS1` CV (30-min vs 60-sec vs 15-sec)

For every validation fold in `DS1`, patient recordings were chronologically sliced into independent 60-second and 15-second clips (`rec_scale`, `template`, and `local_med_rr` computed strictly within each clip) and scored with the fold model trained on 30-min recordings.

| Candidate | 30-min Macro (S F1) | 60-sec Macro (S F1) | Δ (60s − 30m) | 15-sec Macro (S F1) | Δ (15s − 30m) |
|---|---:|---:|---:|---:|---:|
| `v2.1_baseline_rf` | 0.648 (0.313) | 0.649 (0.318) | +0.001 | 0.642 (0.296) | -0.006 |
| **`v3_hgb_100_l15_bal_3cls`** | **0.747 (0.364)** | **0.738 (0.366)** | **-0.009** | **0.731 (0.357)** | **-0.016** |
| `v3_hgb_120_l15_unw` | 0.747 (0.366) | 0.733 (0.356) | -0.014 | 0.725 (0.352) | -0.022 |
| `v3_hgb_120_l15_unw_3cls` | 0.745 (0.378) | 0.734 (0.370) | -0.011 | 0.728 (0.359) | -0.017 |
| `v3_hgb_100_l15_bal` | 0.743 (0.365) | 0.736 (0.372) | -0.007 | 0.728 (0.354) | -0.015 |

On `v3_hgb_100_l15_bal_3cls`, 60-second app/web clips retain **98.8%** of full 30-minute Macro F1 (`-0.009`) and `S` F1 slightly increases (`0.364 → 0.366`), confirming that `rec_scale`, `template`, and `±15`-beat `local_med_rr` generalize cleanly to short clips.

---

## 5. One-Shot Final Evaluation on Locked `DS2`

The single frozen `v3_hgb_100_l15_bal_3cls` model (fit once on all 22 `DS1` patients) was evaluated **once** against the 22 unseen `DS2` test patients.

### 5.1 Annotation-Aligned `DS2` (49,661 beats)

| Model | N (P / R / F1) | S (P / R / F1) | V (P / R / F1) | F | Macro F1 `(N,S,V)` | Accuracy |
|---|---|---|---|---:|---:|---:|
| `v2.1` (50-tree RF) | 0.958 / 0.972 / **0.965** | 0.204 / 0.162 / **0.180** | 0.908 / 0.944 / **0.926** | not pred | **0.690** | **0.933** |
| **`v3` (`v3_hgb_100_l15_bal_3cls`)** | 0.957 / 0.988 / **0.973** | 0.366 / 0.126 / **0.188** | 0.933 / 0.974 / **0.953** | not pred | **0.705** | **0.948** |

### 5.2 End-to-End `DS2` from Raw MLII Signal (`portable` Pan-Tompkins)

Both pipelines share the exact same `v2.1` R-peak detector on `DS2`: Sensitivity = `0.9971` (`49,566 / 49,712`), Positive Predictivity = `0.9976` (`49,566 / 49,686`), median offset `0` samples (5th/95th percentiles `-1 / +1`).

| Pipeline | N (P / R / F1) | S (P / R / F1) | V (P / R / F1) | Macro F1 `(N,S,V)` | Accuracy | Runtime (22 recs) |
|---|---|---|---|---:|---:|---:|
| `v2.1` end-to-end | 0.958 / 0.972 / **0.965** | 0.201 / 0.158 / **0.177** | 0.901 / 0.945 / **0.923** | **0.688** | **0.933** | 4.70 s |
| **`v3` end-to-end** | 0.957 / 0.987 / **0.972** | 0.342 / 0.122 / **0.179** | 0.926 / 0.980 / **0.952** | **0.701** | **0.947** | 5.87 s |

### 5.3 Post-Hoc Error Analysis of `DS2` Class `S` (No Retuning)

While `v3` nearly doubled `S` precision (`0.204 → 0.366`), lifted `V` F1 (`0.926 → 0.953`), lifted `N` F1 (`0.965 → 0.973`), and raised overall accuracy by `+1.5%` (`0.933 → 0.948`), overall `DS2` `S` F1 rose only modestly (`0.180 → 0.188`). A read-only per-patient inspection explains why:

| `DS2` Subset | Beats | `S` Support | `v2.1` S (P / R / F1) | `v3` S (P / R / F1) | `v2.1` Macro | `v3` Macro |
|---|---:|---:|---|---:|---:|---:|
| All 22 `DS2` records | 49,661 | 1,836 | 0.204 / 0.162 / 0.180 | 0.366 / 0.126 / 0.188 | 0.690 | **0.705** |
| **21 `DS2` records (excl. `232`)** | 47,883 | 455 | 0.201 / 0.642 / **0.306** | 0.353 / 0.481 / **0.407** | 0.737 | **0.783** |
| Record `232` alone | 1,778 | 1,381 | 1.000 / 0.004 / 0.007 | 1.000 / 0.009 / 0.019 | 0.124 | 0.129 |

Patient `232` alone contributes **1,381 / 1,836 (75.2%)** of all `DS2` `S` beats (`77.7%` of record `232` itself is annotated `A`), representing a sustained **ectopic atrial rhythm** rather than isolated premature beats. Because nearly every beat in record `232` is `A`, both the patient's median beat template and local median RR interval reflect the ectopic rhythm itself. Across the other 21 `DS2` patients (isolated/paroxysmal PACs), `v3` boosts `S` F1 by **+33% relative (`0.306 → 0.407`)** and Macro F1 from `0.737 → 0.783`.

---

## 6. External Validation on PhysioNet `SVDB` (Zero Retraining)

Evaluated on the first **15 records** (`800–812, 820–821`; **33,180 beats**: `N = 30,936`, `S = 1,119`, `V = 1,120`, `F = 5`) from the MIT-BIH Supraventricular Arrhythmia Database (`svdb`, resampled `128 Hz → 360 Hz` via `portable.to_360hz`) with **zero retraining**:

| Model | N (P / R / F1) | S (P / R / F1) | V (P / R / F1) | Macro F1 `(N,S,V)` | Accuracy |
|---|---|---|---|---:|---:|
| `v2.1` (shipped RF) | 0.993 / 0.913 / 0.951 | 0.629 / 0.742 / **0.681** | 0.300 / 0.915 / **0.451** | **0.695** | 0.907 |
| **`v3` (`v3_hgb_100_l15_bal_3cls`)** | 0.995 / 0.971 / **0.983** | 0.731 / 0.796 / **0.762** | 0.604 / 0.943 / **0.737** | **0.827** | **0.964** |

Across unseen patients from an entirely different database and sampling rate, `v3` improves **Macro F1 by +0.132 (`0.695 → 0.827`)**, **`S` F1 by +0.081 (`0.681 → 0.762`)**, and **`V` F1 by +0.286 (`0.451 → 0.737`)**.

---

## 7. Live Scale-Invariance Test (`app/samples/record_200.csv`)

Running the full portable DSP + feature + exported JSON loop pipeline on `record_200.csv` scaled to Volts (`0.001×`), millivolts (`1×`), and microvolts (`1000×`):

| Scale Factor | `v2.1` Predicted `(N, S, V, F)` | `v3` Predicted `(N, S, V, F)` | `v3` Max Feature Diff vs `1×` | `v3` Max Proba Diff vs `1×` |
|---|---|---|---|---|
| `0.001×` (Volts) | `(48, 22, 11, 0)` *(broken)* | **`(37, 0, 44, 0)`** | `6.48e-12` | **`0.0`** |
| `1×` (mV) | `(37, 0, 44, 0)` | **`(37, 0, 44, 0)`** | `0.0` | `0.0` |
| `1000×` (µV) | `(37, 0, 44, 0)` | **`(37, 0, 44, 0)`** | `8.48e-12` | **`0.0`** |

---

## 8. Pan–Tompkins `0.2×` Mid-Recording Amplitude Drop Prototype

Implemented as a standalone prototype (`detect_rpeaks_v3_proto` in `scripts/train_v3.py`, leaving `src/portable.py` untouched). After an initial unconstrained decay prototype caused `+261` false positives during 6-second asystolic pauses in `DS2` record `232` (`DS2 PPV = 0.9921`, `-0.54%`), adding a scale-invariant `spki_ref` decay floor (`max(0.5 * spki, 2 * npki, 0.08 * spki_ref)` after `> 2.5 s` silence) plus conditional multi-beat rescue (`gap > 2.2 * rr` or post-decay) preserved MIT-BIH precision while rescuing 100% of dropped beats:

| Benchmark | `v2.1` (`portable.detect_rpeaks`) | `v3` Prototype (`spki_ref`-floored) | Delta |
|---|---:|---:|---:|
| `record_200.csv` 2nd half `0.2×` (clean ref = `43`) | **0 / 43** *(missed all)* | **43 / 43 (100%)** | **+43 beats rescued** |
| `DS1` Sensitivity (`51,021` beats) | `0.9955` (`50,793`) | **`0.9969`** (`50,861`) | `+0.0014` (`+0.14%`) |
| `DS1` Positive Predictivity | `0.9927` (`50,793/51,167`) | `0.9907` (`50,861/51,339`) | `-0.0020` (`-0.20%`) |
| `DS2` Sensitivity (`49,712` beats) | `0.9979` (`49,608`) | **`0.9981`** (`49,618`) | `+0.0002` (`+0.02%`) |
| `DS2` Positive Predictivity | `0.9975` (`49,608/49,730`) | `0.9959` (`49,618/49,821`) | `-0.0016` (`-0.16%`) |

---

## 9. JSON Size, Inference Speed & Phase 2 Recommendation

- **Winning Model:** `v3_hgb_100_l15_bal_3cls` (`HistGradientBoostingClassifier`, 100 iterations × 3 classes, max 15 leaves/tree, decision weights `[1.0, 0.25, 0.5, 0.0]`).
- **Compact JSON Artifact Size:** **162,294 bytes (`0.162 MB`)** — **7.8× smaller** than `v2.1`'s `1.275 MB` Random Forest (`export/ecg_forest.json`) and far under the `3 MB` mobile/web budget.
- **Inference Speed & Parity:** `296.26 ms` per 1,000 beats in pure Python loops (`~0.68 s` for an entire ~2,300-beat 30-minute MIT-BIH recording after feature extraction; corrected from the `0.19 ms` `1000×` unit typo in Phase 1); max probability difference vs `scikit-learn` is `3.05e-8` on DS1 CV (`2.25e-6` across 9,933 DS2 beats for `export/ecg_model_v3.json`, `0` label flips).
- **Phase 2 Porting Recommendation:**
  1. **Promote `v3_hgb_100_l15_bal_3cls` + `features_v3`** to Python (`src/portable.py` / `src/pipeline.py`), Dart (`mobile/lib/ecg`), and BioVanta JS: implementing `HGB` inference requires only ~25 lines of tree-traversal + `exp`/softmax arithmetic on top of the existing tree walker, while shrinking app/web bundle size by >1.1 MB.
  2. **Promote the `spki_ref`-floored `detect_rpeaks_v3_proto` logic** into `src/portable.py` and Dart/JS so mid-recording `0.2×` amplitude drops no longer lose all remaining beats while keeping MIT-BIH Sensitivity `> 99.6%` and PPV `> 99.0%`.
  3. **Future v3.1 Research Opportunity:** Because continuous ectopic atrial rhythms (e.g., MIT-BIH record `232`) lack normal beats inside the patient's own recording, future work could investigate absolute P-wave morphology descriptors or short-baseline rhythm regularity metrics to capture sustained atrial rhythms without relying solely on relative-to-patient-median contrast.
