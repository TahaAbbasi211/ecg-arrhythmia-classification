/// Biquad cascade filtering, ported 1:1 from `src/portable.py`.
library;

import 'constants.dart';

/// One second-order section: b0, b1, b2, a0, a1, a2. `a0` is always 1 and unused.
typedef Biquad = List<double>;

/// Parse the `sos_*` arrays of `ecg_config.json` into biquads.
List<Biquad> parseSos(List<dynamic> raw) {
  return raw
      .map((row) => (row as List<dynamic>).map((v) => (v as num).toDouble()).toList())
      .toList();
}

/// Cascade of biquads, direct form II transposed, zero initial state.
List<double> sosFilt(List<Biquad> sos, List<double> x) {
  var y = List<double>.from(x);
  for (final section in sos) {
    final b0 = section[0];
    final b1 = section[1];
    final b2 = section[2];
    final a1 = section[4];
    final a2 = section[5];
    final out = List<double>.filled(y.length, 0.0);
    var z1 = 0.0;
    var z2 = 0.0;
    for (var n = 0; n < y.length; n++) {
      final v = y[n];
      final o = b0 * v + z1;
      z1 = b1 * v - a1 * o + z2;
      z2 = b2 * v - a2 * o;
      out[n] = o;
    }
    y = out;
  }
  return y;
}

/// Zero-phase filtering: odd-extend both ends, filter forward then backward, trim.
///
/// The padding is numpy's `filtfilt` odd extension with `n = min(padlen, len - 1)`:
///   left  = 2*x[0]    - [x[n], x[n-1], ..., x[1]]
///   right = 2*x[last] - [x[last-1], x[last-2], ..., x[last-n]]
List<double> filtFilt(List<Biquad> sos, List<double> x, {int pad = padlen}) {
  final len = x.length;
  if (len == 0) return <double>[];
  final n = pad < len - 1 ? pad : len - 1;
  if (n <= 0) {
    // Degenerate: nothing to pad with, plain forward/backward pass.
    final y = sosFilt(sos, x);
    return sosFilt(sos, y.reversed.toList()).reversed.toList();
  }

  final padded = List<double>.filled(len + 2 * n, 0.0);
  // Left pad: 2*x[0] - x[n], then x[n-1] ... x[1]  (i.e. reversed indices 1..n).
  for (var i = 0; i < n; i++) {
    padded[i] = 2.0 * x[0] - x[n - i];
  }
  for (var i = 0; i < len; i++) {
    padded[n + i] = x[i];
  }
  // Right pad: 2*x[last] - x[last-1], x[last-2], ..., x[last-n].
  final last = len - 1;
  for (var i = 0; i < n; i++) {
    padded[n + len + i] = 2.0 * x[last] - x[last - 1 - i];
  }

  var y = sosFilt(sos, padded);
  y = sosFilt(sos, y.reversed.toList()).reversed.toList();
  return y.sublist(n, y.length - n);
}
