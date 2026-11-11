# ECG Beat Classifier (Android)

Offline Flutter app that classifies heartbeats of a single-lead ECG as **N** (normal),
**S** (supraventricular premature) or **V** (ventricular premature).

Everything runs on the device: filtering, R-peak detection, the 57 beat features and a
50-tree Random Forest are pure Dart. There is no network code, no analytics and no ML
plugin, and the release manifest has no `INTERNET` permission.

> Educational project, not a medical device.

## Requirements

- Flutter 3.47 or newer (Dart 3.13+)
- Android SDK with platform 36 and build-tools 35.0.0
- Android NDK 28.2.13676358 (pinned in `android/app/build.gradle.kts`)
- JDK 21

Check the toolchain first:

```bash
flutter doctor -v
```

## Build notes

The Android shell is pinned rather than left on the newest defaults, because
Flutter 3.47's Gradle plugin does not work with the newest Android Gradle Plugin:

- **AGP 8.11.1** in `android/settings.gradle.kts`. AGP 9 enables `android.newDsl`,
  which the Flutter Gradle plugin cannot read yet.
- **NDK 28.2.13676358** pinned explicitly. Without the pin AGP 8.11.1 asks for
  NDK 27, while Flutter provisions 28.
- **`kotlin.incremental=false`** in `android/gradle.properties`. The Kotlin
  incremental cache fails to close when the build directory is locked or
  sandboxed; disabling it only costs build time, not APK quality.
- If `dl.google.com` is unreachable on your network, the Gradle build cannot
  resolve AGP or AndroidX. An init script at `~/.gradle/init.d/mirrors.gradle`
  that adds a Google Maven mirror fixes it without touching this repo.

## Build

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

The APKs land in `build/app/outputs/flutter-apk/`:

| APK | Size |
|---|---|
| `app-armeabi-v7a-release.apk` | 14.15 MB |
| `app-arm64-v8a-release.apk` | 16.63 MB |
| `app-x86_64-release.apk` | 18.06 MB |

Install one on a connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The release APK requests no permissions at all beyond Flutter's internal
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; there is no `INTERNET` permission.

## Tests

`test/portable_test.dart` replays the golden vectors in `../export/test_vectors.json`,
produced by the Python reference (`src/portable.py`). It checks, for each of the three
recordings:

| Check | Tolerance |
|---|---|
| `filtFilt(raw)` vs `filtered` | max abs diff ≤ 1e-6 |
| `detectRPeaks(filtered)` vs `detected_peaks` | exact |
| `beatFeatures` vs `features` | \|a−b\| ≤ 1e-6 + 1e-6·\|b\| |
| `Forest.predictProba` vs `proba` | abs diff ≤ 1e-5 |
| `analyze(raw, 360)` vs `used_peaks`, `pred`, `proba` | exact / exact / 1e-5 |

The test file reads the vectors from the repo, so `export/test_vectors.json` is
deliberately **not** bundled into the app.

Three more suites cover the app itself, so `flutter test` runs 28 tests in total:

- `test/ui_test.dart` — the CSV parser (header, one-per-line, comma separated,
  first numeric column) and the home/about screens, including the rate validation
  and the "pick a record first" message.
- `test/result_screen_test.dart` — the four summary cards, the plot, the window
  slider, the legend and the S/V beat list with tap-to-jump.
- `test/isolate_test.dart` — the real isolate path end to end: record 200 gives
  81 beats (37 N, 0 S, 44 V) at 89.3 bpm, matching `portable.analyze_reference`,
  and a flat signal reports no beats.

Measured performance: `analyze()` on a 30-minute signal (650,000 samples) takes
about 0.6–0.9 s on this machine, and it runs in a background isolate on the phone.

## Layout

```
lib/
  ecg/            pure Dart, no Flutter imports
    constants.dart    FS, PRE/POST, R, weights
    stats.dart        numpy-compatible median / argmax / argmin
    filter.dart       sosFilt, filtFilt (odd-extension padding, padlen 720)
    resample.dart     resampleLinear to 360 Hz
    rpeaks.dart       detectRPeaks (Pan-Tompkins style)
    features.dart     beatFeatures (57 values)
    forest.dart       Forest.fromJson, predictProba (float32 casts)
    analyze.dart      EcgConfig, EcgAnalyzer.analyze
  data/           asset loading, CSV parsing, isolate worker
  ui/             home, result, about screens, plot painter, theme
assets/
  ecg_config.json   filter coefficients + decision weights
  ecg_forest.json   the 50 exported trees
  samples/*.csv     three 60 s demo records at 360 Hz
```

## Porting notes

The Dart code mirrors `src/portable.py` line for line. The details that are easy to get
wrong, and are handled explicitly:

- `np.median` with an even count is the mean of the two middle values.
- `argmax` / `argmin` / `max(..., key=...)` return the **first** index on ties.
- `filtfilt` odd extension: `n = min(720, len - 1)`, `left = 2*x[0] - x[n..1]`,
  `right = 2*x[-1] - x[-2..-n-1]`, trim `n` on each side.
- Biquads are direct form II transposed with zero initial state; `a0` is unused.
- Standard deviation, skewness and excess kurtosis are population (biased) moments;
  skewness and kurtosis are 0 when `m2 <= 1e-12`.
- Features are rounded to float32 before being compared with the float64 thresholds,
  matching scikit-learn.
- The recording-level median R-R uses only the beats that are actually analyzed.

## Data and results

MIT-BIH Arrhythmia Database, first lead (MLII) only. Inter-patient split: 22 training
and 22 different test patients.

| Class | F1 |
|---|---|
| N | 0.965 |
| V | 0.926 |
| S | 0.180 |
| Macro F1 (N, S, V) | 0.69 |

Limitations: S beats are weak, fusion (F) beats are not predicted, single lead, one
database.
