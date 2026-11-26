/// HistGradientBoosting inference over exported float64 trees,
/// ported 1:1 from `hgb_predict_proba` and `effective_scores` in `src/portable.py`.
///
/// NOTE: Never use Float32List in the HGB path; thresholds and feature values
/// must be compared strictly in IEEE-754 float64 (`double`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One exported HGB decision tree. Node `i` is a leaf when `left[i] == -1`.
class HgbTree {
  HgbTree({
    required this.feature,
    required this.threshold,
    required this.left,
    required this.right,
    required this.value,
  });

  final Int32List feature;
  final Float64List threshold;
  final Int32List left;
  final Int32List right;
  final Float64List value;

  factory HgbTree.fromJson(Map<String, dynamic> json) {
    final feature = json['feature'] as List<dynamic>;
    final threshold = json['threshold'] as List<dynamic>;
    final left = json['left'] as List<dynamic>;
    final right = json['right'] as List<dynamic>;
    final value = json['value'] as List<dynamic>;
    return HgbTree(
      feature: Int32List.fromList([for (final v in feature) (v as num).toInt()]),
      threshold: Float64List.fromList(
        [for (final v in threshold) (v as num).toDouble()],
      ),
      left: Int32List.fromList([for (final v in left) (v as num).toInt()]),
      right: Int32List.fromList([for (final v in right) (v as num).toInt()]),
      value: Float64List.fromList([for (final v in value) (v as num).toDouble()]),
    );
  }
}

/// Exported HistGradientBoostingClassifier (`export/ecg_model_v3.json`).
class HgbModel {
  HgbModel({
    required this.schemaVersion,
    required this.kind,
    required this.classes,
    required this.nClasses,
    required this.featureCount,
    required this.decisionWeights,
    required this.baseline,
    required this.iterations,
  });

  final int schemaVersion;
  final String kind;
  final List<int> classes;
  final int nClasses;
  final int featureCount;
  final List<double> decisionWeights;
  final Float64List baseline;
  final List<List<HgbTree>> iterations;

  factory HgbModel.fromJson(Map<String, dynamic> json) {
    final kind = (json['kind'] as String?) ?? 'hgb';
    if (kind != 'hgb') {
      throw FormatException('Expected model kind "hgb", got "$kind"');
    }
    final classes = [
      for (final c in json['classes'] as List<dynamic>) (c as num).toInt(),
    ];
    final baseline = Float64List.fromList([
      for (final v in json['baseline'] as List<dynamic>) (v as num).toDouble(),
    ]);
    final iterations = <List<HgbTree>>[
      for (final it in json['iterations'] as List<dynamic>)
        [
          for (final t in it as List<dynamic>)
            HgbTree.fromJson(t as Map<String, dynamic>),
        ],
    ];
    final weightsJson = json['decision_weights'] as List<dynamic>?;
    final weights = weightsJson == null
        ? const <double>[1.0, 0.25, 0.5, 0.0]
        : [for (final w in weightsJson) (w as num).toDouble()];

    return HgbModel(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 3,
      kind: kind,
      classes: classes,
      nClasses: (json['n_classes'] as num?)?.toInt() ?? 4,
      featureCount: (json['feature_count'] as num?)?.toInt() ?? 84,
      decisionWeights: weights,
      baseline: baseline,
      iterations: iterations,
    );
  }

  /// Predict 4-class probabilities for one 84-element float64 feature vector.
  List<double> predictProba(List<double> x) {
    if (x.length != featureCount) {
      throw ArgumentError.value(
        x.length,
        'features.length',
        'expected $featureCount features, got ${x.length}',
      );
    }
    for (var i = 0; i < featureCount; i++) {
      if (!x[i].isFinite) {
        // missing_go_to_left is not exported; refuse NaN/Inf instead of
        // silently branching right in every tree.
        throw ArgumentError.value(
          x[i],
          'features[$i]',
          'beat features must be finite, not NaN or Inf',
        );
      }
    }

    final raw = Float64List.fromList(baseline);
    final kCls = raw.length;
    for (final iterTrees in iterations) {
      for (var c = 0; c < kCls; c++) {
        final tree = iterTrees[c];
        final left = tree.left;
        final right = tree.right;
        final feat = tree.feature;
        final thr = tree.threshold;
        var i = 0;
        while (left[i] != -1) {
          i = x[feat[i]] <= thr[i] ? left[i] : right[i];
        }
        raw[c] += tree.value[i];
      }
    }

    var maxRaw = raw[0];
    for (var c = 1; c < kCls; c++) {
      if (raw[c] > maxRaw) maxRaw = raw[c];
    }
    final exps = Float64List(kCls);
    var sumExp = 0.0;
    for (var c = 0; c < kCls; c++) {
      final e = math.exp(raw[c] - maxRaw);
      exps[c] = e;
      sumExp += e;
    }

    final out = List<double>.filled(nClasses, 0.0);
    for (var idx = 0; idx < classes.length; idx++) {
      out[classes[idx]] = exps[idx] / sumExp;
    }
    return out;
  }
}

/// Normalize decision-weighted scores: `(proba * weights) / sum(proba * weights)`.
///
/// Falls back to a copy of [proba] when the weighted sum is not positive.
List<double> effectiveScores(List<double> proba, List<double> weights) {
  final n = proba.length;
  final wp = List<double>.filled(n, 0.0);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final v = proba[i] * weights[i];
    wp[i] = v;
    sum += v;
  }
  if (sum <= 0.0) {
    return List<double>.from(proba);
  }
  return [for (final v in wp) v / sum];
}
