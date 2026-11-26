# ECG Arrhythmia Classification

Classifies individual heartbeats from single-lead ECG signals as **Normal (N)**, **Supraventricular premature (S)** or **Ventricular premature (V)** using machine learning. Includes a Streamlit demo and a **fully offline Android app** powered by the **v3.1.0** engine (`HistGradientBoosting` + 84 scale-invariant features).

> **Disclaimer:** Research and non-clinical software — not a certified medical device and not intended for clinical diagnosis or treatment decisions.

![App screenshot](docs/app_demo.png)

**[Download the Android app (APK)](https://github.com/TahaAbbasi211/ecg-arrhythmia-classification/releases/latest)**: runs fully offline, no data leaves the phone.

## Highlights

- **Scale-invariant v3.1 engine**: beats are median-centered and normalized by the recording median peak-to-peak amplitude (`rec_scale`), so Volts (`0.001×`), millivolts (`1×`), and microvolts (`1000×`) produce identical predictions
- **Full pipeline from the raw signal**: zero-phase filtering, Pan-Tompkins R-peak detection, beat segmentation, 84-feature extraction (`src/features_v3.py`), and pure `float64` gradient-boosted tree inference
- **Zero-leakage inter-patient evaluation**: all model selection, ablations, and decision-weight tuning were frozen strictly inside 5-fold patient-grouped CV on `DS1` before evaluating `DS2` once, plus zero-retraining external validation on PhysioNet `SVDB`
- **Single source of truth (`export/ecg_model_v3.json`)**: `163 KB` compact JSON model (`7.8×` smaller than `v2.1`'s `1.275 MB` Random Forest), run directly in Python, Streamlit, and Dart without runtime `scikit-learn` or `scipy` dependencies
- **Cross-language parity**: Python (`src/portable.py`) and Dart (`mobile/lib/ecg`) are verified against golden vectors (`export/test_vectors.json`) within `1e-10` on all 84 features and `1e-6` on probabilities/scores
- **Honest reporting of failures** (see Limitations and [docs/v3_experiment_report.md](docs/v3_experiment_report.md))

## Dataset

[MIT-BIH Arrhythmia Database](https://physionet.org/content/mitdb/1.0.0/) (PhysioNet): 48 half-hour two-lead recordings at 360 Hz with beat-by-beat expert annotations. Only lead MLII is used.

- Annotations are grouped into the standard AAMI classes (`N, S, V, F, Q`).
- The four paced records (`102, 104, 107, 217`) are excluded, following AAMI recommendations.
- Patient-wise split from de Chazal et al. (2004): 22 records for training (`DS1`, 50,969 beats), 22 different records for testing (`DS2`, 49,661 beats).
- The `Q` class has only 15 beats after excluding paced records, so it is dropped.
- External generalization check: first 15 records (`800–812, 820–821`, 33,180 beats, `128 Hz → 360 Hz`) of PhysioNet `SVDB` with zero retraining.

The data is not stored in this repo; notebook 01 (or `scripts/train_v3.py`) downloads MIT-BIH from PhysioNet.

## Method (`v3.1.0`)

1. **Preprocessing**: Butterworth band-pass filter (`0.5` to `40` Hz, zero-phase), then each beat is cut as `90` samples before and `110` samples after the R-peak (`200` samples at `360 Hz`).
2. **Features (`84`, `src/features_v3.py`)**:
   - **Local rhythm (`14`)**: `±15`-beat local median RR, IQR variability, compensatory pause ratio, prematurity z-score, and adjacent RR ratios.
   - **Scale-invariant morphology (`52`)**: computed on `x_rec` (beat median-centered and divided by `rec_scale = max(median(beat_p2p), 1e-8)`): `12` amplitude/duration/moment scalars and `40` downsampled shape points.
   - **Recording median template (`9`)**: Pearson correlation and RMS difference against the recording's element-wise median beat over P/PR, QRS, T/ST, and the full beat, plus `corr_qrs - corr_p`.
   - **Regional P/T descriptors (`9`)**: P-to-QRS and T-to-QRS energy ratios, P/T extrema, peak position, and deviations from the median template.
3. **Model**: `HistGradientBoostingClassifier` (`max_iter=100` with early stopping at `65` iterations × `3` classes `N, S, V`, `max_leaf_nodes=15`, `learning_rate=0.08`, `min_samples_leaf=30`, `l2_regularization=1.0`, `sample_weight="balanced"`). Per-class decision weights `[1.0, 0.25, 0.5, 0.0]` were tuned on out-of-fold predictions from `DS1` 5-fold patient-grouped CV only. Exported to `export/ecg_model_v3.json` (`163,323` bytes, unrounded `float64` split thresholds).
4. **Inference & scores** (`src/portable.py`): linear resampling to `360 Hz` (with 3rd-order `150 Hz` Butterworth anti-aliasing above `360 Hz`), zero-phase biquad filtering, Pan-Tompkins R-peak detection, 84-feature extraction, and `float64` HGB traversal with an `isfinite` input guard. UIs display the normalized effective score `(proba * weights) / sum(proba * weights)` (`score`, relative and uncalibrated) instead of raw probabilities.

## Results

### MIT-BIH `DS2` (22 unseen test patients, end to end from the raw signal)

R-peak detection finds `99.71%` of annotated beats (`49,566 / 49,712`, positive predictivity `99.76%`). Median offset to the expert annotation is `0` samples (5th/95th percentile: `-1 / +1`).

| Class | Precision | Recall | F1 (`v3.1`) | F1 (`v2.1`) | Beats |
|---|---|---|---|---|---|
| `N` (normal) | 0.957 | 0.987 | **0.972** | 0.965 | 44,169 |
| `S` (supraventricular premature) | 0.342 | 0.122 | **0.179** *(0.407 excl. `232`)* | 0.177 | 1,825 |
| `V` (ventricular premature) | 0.926 | 0.980 | **0.952** | 0.923 | 3,183 |
| `F` (fusion) | not predicted | — | — | — | 383 |

Overall accuracy **`0.947`** (up from `0.933`), macro F1 over `N, S, V`: **`0.701`** (up from `0.688`).

### External validation on PhysioNet `SVDB` (15 records, `128 Hz → 360 Hz`, zero retraining)

| Model | N F1 | S F1 | V F1 | Macro F1 `(N, S, V)` | Accuracy |
|---|---|---|---|---|---|
| `v2.1` (shipped RF) | 0.951 | 0.681 | 0.451 | 0.695 | 90.7% |
| **`v3.1` (`HGB`, 84 features)** | **0.983** | **0.762** | **0.737** | **0.827** | **96.4%** |

## Android app

- **Fully offline (`V3.1.0`)**: no internet permission, all processing and the `163 KB` `ecg_model_v3.json` run on the phone (`mobile/assets/ecg_forest.json` removed, shrinking the bundle by >1.1 MB). English and Persian (RTL), switchable in the app.
- Pure `float64` Dart port in `mobile/lib/ecg` (`features_v3.dart`, `hgb_model.dart`, `analyze.dart`, `rpeaks.dart`, `filter.dart`, `resample.dart`). Golden test vectors (`export/test_vectors.json`) verify exact peak/class agreement, `< 1e-10` on all 84 features, `< 1e-6` on probabilities/scores, and `0.001× / 1× / 1000×` scale invariance.
- Build instructions and signing: see [mobile/README.md](mobile/README.md) and [mobile/android/SIGNING.md](mobile/android/SIGNING.md).

## Limitations

- **Sustained ectopic atrial rhythms (`S` class & record `232`):** Patient `232` alone contributes `1,381 / 1,836` (`75.2%`) of `DS2`'s annotated `S` beats (`77.7%` of record `232` itself is annotated `A`). Because nearly the entire strip is ectopic, the recording-median template and local median RR adapt to the ectopic rhythm rather than normal sinus beats. Excluding record `232`, `v3.1` achieves **`0.407` `S` F1** and **`0.783` Macro F1** across the remaining 21 `DS2` patients (and `0.762` `S` F1 on `SVDB`).
- **Fusion (`F`) beats are not predicted:** `372 / 414` (`89.9%`) of `DS1` fusion beats come from patient `208` alone; tuning an `F` weight in `DS1` CV caused `> 90%` false-alarm rates, so `w_F = 0` and the production model is trained strictly on `N, S, V`.
- **Uncalibrated `score`:** The `score` shown in the Streamlit table and Android beat rows is `(proba * decision_weights) / sum(proba * decision_weights)`, a relative ranking score that is not calibrated to clinical event probabilities.
- **Scope:** Single lead (`MLII` / equivalent) only; evaluated on MIT-BIH and SVDB research datasets, not validated on clinical devices or broader patient populations.

## Run the Streamlit app

```bash
pip install -r requirements.txt
streamlit run app/streamlit_app.py
```

Pick a demo sample or upload a CSV/TXT file. Accepted input:

- one column of ECG samples, or two columns `(time, ecg)` — the time column is detected and ignored;
- a header line with names (a text first line is treated as the header);
- `,`, `;` or tab separators, `#` or `//` comment lines, and a UTF-8 BOM.

Set the sampling rate, choose the input unit (`mV` by default), and invert polarity if upside down. Classification is scale-invariant (`V`, `mV`, `uV`), while selecting the right unit keeps the `mV` plot axis accurate; the app warns when filtered amplitude suggests a unit mismatch.

## Tests & Scripts

```bash
pip install -r requirements-dev.txt
pytest -v                 # parsing, DSP, v3 features, HGB parity, pipeline, app smoke tests
cd mobile
flutter analyze
flutter test              # golden vectors, 84-feature & float64 HGB parity, scale invariance, UI/l10n
```

- `python scripts/export_v3_model.py`: trains the frozen `v3.1` `HGB` model on `DS1`, exports `export/ecg_model_v3.json`, updates `export/ecg_config.json`, verifies `< 1e-5` parity & `0` label flips on `DS2`, and benchmarks Python loop speed (`~296 ms / 1k beats`).
- `python scripts/evaluate_ds2.py`: reproduces the end-to-end `DS2` numbers above (`--scipy` switches to the `wfdb`/XQRS reference).
- `python scripts/export_test_vectors.py`: regenerates `export/test_vectors.json` (`--check` verifies disk parity).
- `python scripts/export_resample_parity.py`: regenerates `export/resample_parity.json`.

## Project structure

```
app/            Streamlit app, shared signal-file parsing and demo samples
export/         Single-source-of-truth v3.1 model (JSON), config, golden vectors, resampling fixture
mobile/         Offline Flutter (Android) app (V3.1.0)
models/         Legacy v2.1 joblib models (supported via load_model(path) for compatibility)
notebooks/      Phase 0/v2 step-by-step research notebooks
scripts/        v3 research benchmark, model export, DS2 evaluation, golden-vector/parity export
src/            v3 features (84 cols), inference pipeline and portable reference implementation
tests/          pytest suite (parsing, DSP, v3 features, HGB parity, pipeline, app smoke tests)
docs/           Experiment reports, results JSON, README images
```

## References

- Moody GB, Mark RG. The impact of the MIT-BIH Arrhythmia Database. IEEE Eng Med Biol 20(3):45-50, 2001.
- Goldberger AL et al. PhysioBank, PhysioToolkit, and PhysioNet. Circulation 101(23):e215-e220, 2000.
- de Chazal P, O'Dwyer M, Reilly RB. Automatic classification of heartbeats using ECG morphology and heartbeat interval features. IEEE Trans Biomed Eng 51(7):1196-1206, 2004.

## License

MIT - see [LICENSE](LICENSE).
