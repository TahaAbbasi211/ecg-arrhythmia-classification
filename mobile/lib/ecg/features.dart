/// The 57 beat features, ported 1:1 from `beat_features` in `src/portable.py`.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'stats.dart';

/// Features of one beat (200 samples) and its neighbouring R-R intervals, in samples.
///
/// Order is exactly the reference order:
///   [prevRr, nextRr, prevRr/nextRr, prevRr/medRr, nextRr/medRr,
///    ampR, peak, trough, p2p, tPeak, tTrough, width, energy, area, sd, sk, ku,
///    shape[0..39]]
List<double> beatFeatures(
  List<double> beat,
  int prevRr,
  int nextRr,
  double medRr,
) {
  final n = beat.length;
  final med = median(beat);
  final x = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    x[i] = beat[i] - med;
  }

  var peak = x[0];
  var trough = x[0];
  var absMax = x[0].abs();
  for (var i = 1; i < n; i++) {
    if (x[i] > peak) peak = x[i];
    if (x[i] < trough) trough = x[i];
    final a = x[i].abs();
    if (a > absMax) absMax = a;
  }
  final p2p = peak - trough;
  final ampR = x[rPos];
  final tPeak = argMax(x) - rPos;
  final tTrough = argMin(x) - rPos;

  // QRS width estimate: samples above 30% of the largest absolute deviation.
  final thr = 0.3 * absMax;
  var width = 0;
  final wLo = rPos - 40 < 0 ? 0 : rPos - 40;
  final wHi = rPos + 40 > n ? n : rPos + 40;
  for (var i = wLo; i < wHi; i++) {
    if (x[i].abs() > thr) width++;
  }

  var energy = 0.0;
  var area = 0.0;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    energy += x[i] * x[i];
    area += x[i].abs();
    sum += x[i];
  }
  final mean = sum / n;

  // Population (biased) moments, as numpy computes them.
  var m2 = 0.0;
  var m3 = 0.0;
  var m4 = 0.0;
  for (var i = 0; i < n; i++) {
    final dev = x[i] - mean;
    final d2 = dev * dev;
    m2 += d2;
    m3 += d2 * dev;
    m4 += d2 * d2;
  }
  m2 /= n;
  m3 /= n;
  m4 /= n;

  final sd = math.sqrt(m2);
  double sk;
  double ku;
  if (m2 > 1e-12) {
    // numpy: m3 / m2 ** 1.5 and m4 / m2 ** 2 - 3.0
    sk = m3 / math.pow(m2, 1.5);
    ku = m4 / math.pow(m2, 2) - 3.0;
  } else {
    sk = 0.0;
    ku = 0.0;
  }

  final shapeDen = p2p + 1e-8;
  final out = List<double>.filled(featureCount, 0.0);
  out[0] = prevRr.toDouble();
  out[1] = nextRr.toDouble();
  out[2] = prevRr / nextRr;
  out[3] = prevRr / medRr;
  out[4] = nextRr / medRr;
  out[5] = ampR;
  out[6] = peak;
  out[7] = trough;
  out[8] = p2p;
  out[9] = tPeak.toDouble();
  out[10] = tTrough.toDouble();
  out[11] = width.toDouble();
  out[12] = energy;
  out[13] = area;
  out[14] = sd;
  out[15] = sk;
  out[16] = ku;
  // shape = x[::5] / (p2p + 1e-8): 40 values for a 200-sample beat.
  for (var i = 0; i < 40; i++) {
    out[17 + i] = x[i * 5] / shapeDen;
  }
  return out;
}
