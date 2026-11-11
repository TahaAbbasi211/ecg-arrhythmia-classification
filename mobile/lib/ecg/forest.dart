/// Random Forest evaluation over the exported plain lists, ported from `src/portable.py`.
library;

import 'dart:typed_data';

/// One exported decision tree. Node `i` is a leaf when `left[i] == -1`.
class Tree {
  Tree({
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

  /// Leaf probabilities, indexed by node. Only leaf entries are non-null.
  final List<List<double>?> value;

  factory Tree.fromJson(Map<String, dynamic> json) {
    final feature = json['feature'] as List<dynamic>;
    final threshold = json['threshold'] as List<dynamic>;
    final left = json['left'] as List<dynamic>;
    final right = json['right'] as List<dynamic>;
    final value = json['value'] as List<dynamic>;
    final n = feature.length;
    return Tree(
      feature: Int32List.fromList([for (final v in feature) (v as num).toInt()]),
      threshold: Float64List.fromList([for (final v in threshold) (v as num).toDouble()]),
      left: Int32List.fromList([for (final v in left) (v as num).toInt()]),
      right: Int32List.fromList([for (final v in right) (v as num).toInt()]),
      value: List<List<double>?>.generate(n, (i) {
        final v = value[i];
        if (v == null) return null;
        return [for (final p in v as List<dynamic>) (p as num).toDouble()];
      }),
    );
  }
}

/// The exported forest: 50 trees over 4 classes.
class Forest {
  Forest(this.trees, {this.nClasses = 4});

  final List<Tree> trees;
  final int nClasses;

  factory Forest.fromJson(Map<String, dynamic> json) {
    final trees = (json['trees'] as List<dynamic>)
        .map((t) => Tree.fromJson(t as Map<String, dynamic>))
        .toList();
    return Forest(trees, nClasses: (json['nClasses'] ?? json['n_classes'] ?? 4) as int);
  }

  /// Average of the leaf probabilities of all trees, like sklearn's predict_proba.
  ///
  /// sklearn casts features to float32 before comparing them with the float64
  /// thresholds, so each feature is rounded to float32 first.
  List<double> predictProba(List<double> x) {
    final x32 = Float32List.fromList(x);
    final total = List<double>.filled(nClasses, 0.0);
    for (final tree in trees) {
      var i = 0;
      while (tree.left[i] != -1) {
        // Compare the float32-rounded value as a double, exactly like numpy.
        final v = x32[tree.feature[i]].toDouble();
        i = v <= tree.threshold[i] ? tree.left[i] : tree.right[i];
      }
      final leaf = tree.value[i];
      if (leaf == null) {
        throw StateError('Tree node $i is a leaf but has no probabilities');
      }
      for (var c = 0; c < nClasses; c++) {
        total[c] += leaf[c];
      }
    }
    final n = trees.length;
    return [for (final s in total) s / n];
  }
}
