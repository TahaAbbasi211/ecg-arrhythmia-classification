/// Small numeric helpers that reproduce numpy semantics exactly.
library;

/// numpy.median: for an even number of values, the mean of the two middle ones.
double median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final s = List<double>.from(values)..sort();
  final n = s.length;
  if (n.isOdd) return s[n ~/ 2];
  return (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2.0;
}

/// numpy.argmax: returns the FIRST index on ties.
int argMax(List<double> values) {
  var best = 0;
  var bestValue = values[0];
  for (var i = 1; i < values.length; i++) {
    if (values[i] > bestValue) {
      bestValue = values[i];
      best = i;
    }
  }
  return best;
}

/// numpy.argmin: returns the FIRST index on ties.
int argMin(List<double> values) {
  var best = 0;
  var bestValue = values[0];
  for (var i = 1; i < values.length; i++) {
    if (values[i] < bestValue) {
      bestValue = values[i];
      best = i;
    }
  }
  return best;
}

/// numpy.argmax over the absolute values: first index on ties.
int argMaxAbs(List<double> values) {
  var best = 0;
  var bestValue = values[0].abs();
  for (var i = 1; i < values.length; i++) {
    final v = values[i].abs();
    if (v > bestValue) {
      bestValue = v;
      best = i;
    }
  }
  return best;
}
