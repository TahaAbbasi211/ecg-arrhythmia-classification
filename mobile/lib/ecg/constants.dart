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

/// Number of features produced by [beatFeatures].
const int featureCount = 57;

/// Class names as exported by the Python reference.
const List<String> classNames = ['N', 'S', 'V', 'F'];

/// Per-class decision weights applied to the predicted probabilities.
const List<double> decisionWeights = [1.0, 2.0, 1.0, 0.0];

/// Default zero-phase filter padding.
const int padlen = 720;

/// Refractory period in samples (0.2 s).
const int refractory = 72;

/// Peak refinement radius in samples (0.08 s).
const int refineRadius = 28;

/// Half window of the moving-wave integration (0.15 s / 2).
const int mwiHalf = 27;
