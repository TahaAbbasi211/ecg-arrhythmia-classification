/// Constants shared by the whole portable pipeline.
///
/// These mirror `src/portable.py` exactly. Do not change them without changing
/// the Python reference first.
library;

/// Sampling rate the model was trained on.
const int fs = 360;

/// Samples before / after each R-peak in a beat window.
const int pre = 90;
const int post = 110;

/// Position of the R-peak inside a beat window.
const int rPos = 90;

/// Length of one beat window (pre + post).
const int beatLength = pre + post;

/// Number of features produced by v3 [extractRecordingFeaturesV3].
const int featureCount = 84;

/// Scale-invariance epsilon matching `src/features_v3.py`.
const double featureEps = 1e-8;

/// Half window (in beats) for local R-R rhythm statistics (+/-15 beats).
const int localRrHalfWin = 15;

/// Clinical sub-windows inside a 200-sample beat window at 360 Hz.
const int pStart = rPos - 80;   // 10
const int pEnd = rPos - 20;     // 70
const int qrsStart = rPos - 30; // 60
const int qrsEnd = rPos + 30;   // 120
const int tStart = rPos + 25;   // 115
const int tEnd = rPos + 100;    // 190

/// Class names as exported by the Python reference.
const List<String> classNames = ['N', 'S', 'V', 'F'];

/// Per-class decision weights applied to the predicted probabilities.
const List<double> decisionWeights = [1.0, 0.25, 0.5, 0.0];

/// Default zero-phase filter padding.
const int padlen = 720;

/// Refractory period in samples (0.2 s).
const int refractory = 72;

/// Peak refinement radius in samples (0.08 s).
const int refineRadius = 28;

/// Half window of the moving-wave integration (0.15 s / 2).
const int mwiHalf = 27;
