/// Linear-interpolation resampling, ported from `src/portable.py`.
library;

import 'constants.dart';

/// Resample [x] from [srcFs] to 360 Hz with linear interpolation.
///
/// Returns [x] unchanged when the source rate already rounds to 360 Hz.
List<double> resampleLinear(List<double> x, double srcFs, {int target = fs}) {
  if (srcFs.round() == target) return List<double>.from(x);
  final nOut = (x.length * target / srcFs).toInt();
  if (nOut <= 0 || x.isEmpty) return <double>[];

  final out = List<double>.filled(nOut, 0.0);
  final nIn = x.length;
  for (var i = 0; i < nOut; i++) {
    // t = i * srcFs / target, in source-sample units.
    final t = i * srcFs / target;
    if (t <= 0) {
      out[i] = x[0];
      continue;
    }
    if (t >= nIn - 1) {
      out[i] = x[nIn - 1];
      continue;
    }
    final i0 = t.floor();
    final frac = t - i0;
    out[i] = x[i0] + (x[i0 + 1] - x[i0]) * frac;
  }
  return out;
}
