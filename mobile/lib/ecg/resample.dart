/// Input hygiene, resampling and anti-aliasing, ported 1:1 from `src/portable.py`.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'filter.dart';

/// Fewer samples than this cannot hold a heartbeat.
const int minSamples = 5;

/// Reject a file when more than this share of its samples is NaN or Inf.
const double maxBadFraction = 0.05;

/// Reject a file when one corrupt run is longer than this.
const double maxBadGapSeconds = 0.5;

/// |fs - 360| < fsEpsilon means the signal already is at the target rate.
const double fsEpsilon = 1e-6;

/// Anti-aliasing low-pass corner (Hz) applied before down-sampling.
const double antiAliasCutoff = 150.0;

/// Butterworth order of that pre-filter.
const int antiAliasOrder = 3;

/// Why a signal was refused.
enum SignalProblem { rate, tooShort, tooCorrupt }

/// A signal that cannot be analyzed: bad rate, too short, or too corrupt.
class SignalException implements Exception {
  SignalException(this.message, this.problem);

  final String message;
  final SignalProblem problem;

  @override
  String toString() => message;
}

/// Validate [sampleRate] and return it unchanged.
double checkSampleRate(double sampleRate) {
  if (sampleRate.isNaN || sampleRate.isInfinite || sampleRate <= 0) {
    throw SignalException(
      'The sampling rate must be a positive number, not $sampleRate Hz.',
      SignalProblem.rate,
    );
  }
  return sampleRate;
}

/// Low-pass Butterworth as biquad sections, derived with the bilinear transform.
///
/// An odd order gets one first-order section plus pairs with
/// Q = 1 / (2 sin(pi (2k+1) / 2N)); every section has unity gain at DC.
/// Matches scipy.signal.butter(..., output='sos') to about 1e-16.
List<Biquad> butterworthLowpassSos(
  double sampleRate, {
  double cutoff = antiAliasCutoff,
  int order = antiAliasOrder,
}) {
  final rate = checkSampleRate(sampleRate);
  if (order < 1) {
    throw ArgumentError.value(order, 'order', 'must be at least 1');
  }
  if (cutoff <= 0 || cutoff >= rate / 2) {
    throw ArgumentError.value(cutoff, 'cutoff', 'must be between 0 and Nyquist');
  }

  final sections = <Biquad>[];
  if (order.isOdd) {
    final k = math.tan(math.pi * cutoff / rate);
    final b0 = k / (1.0 + k);
    sections.add(<double>[b0, b0, 0.0, 1.0, (k - 1.0) / (1.0 + k), 0.0]);
  }
  final w0 = 2.0 * math.pi * cutoff / rate;
  final cosW = math.cos(w0);
  final sinW = math.sin(w0);
  for (var i = 0; i < order ~/ 2; i++) {
    final q = 1.0 / (2.0 * math.sin(math.pi * (2 * i + 1) / (2.0 * order)));
    final alpha = sinW / (2.0 * q);
    final a0 = 1.0 + alpha;
    final b0 = (1.0 - cosW) / 2.0 / a0;
    sections.add(<double>[
      b0,
      (1.0 - cosW) / a0,
      b0,
      1.0,
      -2.0 * cosW / a0,
      (1.0 - alpha) / a0,
    ]);
  }
  return sections;
}

/// Validate [x] and linearly interpolate scattered NaN / Inf samples.
///
/// Like numpy.interp, values outside the good range are clamped to the nearest
/// good sample. A file that is mostly broken, or that lost more than
/// [MaxBadGapSeconds] in one run, is refused instead of guessed.
List<double> sanitizeSignal(
  List<double> x,
  double sampleRate, {
  int minLength = minSamples,
  double badFraction = maxBadFraction,
  double badGapSeconds = maxBadGapSeconds,
}) {
  final rate = checkSampleRate(sampleRate);
  if (x.length < minLength) {
    throw SignalException(
      'The signal is too short: ${x.length} samples, at least $minLength needed.',
      SignalProblem.tooShort,
    );
  }

  var bad = 0;
  for (final v in x) {
    if (!v.isFinite) bad++;
  }
  if (bad == 0) return List<double>.from(x);

  if (bad > badFraction * x.length) {
    throw SignalException(
      'Too many invalid samples: $bad of ${x.length} are NaN or Inf.',
      SignalProblem.tooCorrupt,
    );
  }

  var longest = 0;
  var run = 0;
  for (final v in x) {
    if (v.isFinite) {
      run = 0;
    } else {
      run++;
      if (run > longest) longest = run;
    }
  }
  if (longest / rate > badGapSeconds) {
    throw SignalException(
      'A gap of $longest samples is longer than $badGapSeconds s.',
      SignalProblem.tooCorrupt,
    );
  }

  final out = List<double>.from(x);
  var i = 0;
  while (i < out.length) {
    if (out[i].isFinite) {
      i++;
      continue;
    }
    final start = i;
    while (i < out.length && !out[i].isFinite) {
      i++;
    }
    final end = i;
    final left = start - 1;
    if (left < 0) {
      final fill = end < out.length ? out[end] : 0.0;
      for (var k = start; k < end; k++) {
        out[k] = fill;
      }
    } else if (end >= out.length) {
      final fill = out[left];
      for (var k = start; k < end; k++) {
        out[k] = fill;
      }
    } else {
      final v0 = out[left];
      final v1 = out[end];
      final span = end - left;
      for (var k = start; k < end; k++) {
        out[k] = v0 + (v1 - v0) * ((k - left) / span);
      }
    }
  }
  return out;
}

/// Resample to [target] Hz, low-pass filtering first when the source is faster.
///
/// Without that anti-aliasing filter, content above 180 Hz folds down into the
/// ECG band and can invent beats. The 150 Hz corner is 0.4 x 360 Hz, so the
/// response is still 0.707 at the corner and well down by 180 Hz.
List<double> to360Hz(
  List<double> x,
  double sourceFs, {
  int target = fs,
  double cutoff = antiAliasCutoff,
  int order = antiAliasOrder,
}) {
  final rate = checkSampleRate(sourceFs);
  if ((rate - target).abs() < fsEpsilon) return List<double>.from(x);
  var source = x;
  if (rate > target) {
    source = filtFilt(
      butterworthLowpassSos(rate, cutoff: cutoff, order: order),
      x,
    );
  }
  return resampleLinear(source, rate, target: target);
}

/// Resample [x] from [srcFs] to [target] Hz with linear interpolation.
///
/// Returns [x] unchanged when the source rate already is [target].
List<double> resampleLinear(List<double> x, double srcFs, {int target = fs}) {
  final rate = checkSampleRate(srcFs);
  if ((rate - target).abs() < fsEpsilon) return List<double>.from(x);
  if (x.isEmpty) return <double>[];
  final nOut = (x.length * target / rate).toInt();
  if (nOut <= 0) return <double>[];

  final out = List<double>.filled(nOut, 0.0);
  final nIn = x.length;
  for (var i = 0; i < nOut; i++) {
    // t = i * srcFs / target, in source-sample units.
    final t = i * rate / target;
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