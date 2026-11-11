/// Pan-Tompkins style R-peak detector, ported 1:1 from `src/portable.py`.
library;

import 'constants.dart';
import 'filter.dart';
import 'stats.dart';

/// Detect R-peaks in [xf], a signal already band-passed 0.5-40 Hz.
///
/// [sosDet] is the 5-15 Hz detector filter from `ecg_config.json`.
/// Returns sample indices, ascending.
List<int> detectRPeaks(List<double> xf, List<Biquad> sosDet, {int sampleRate = fs}) {
  final n = xf.length;
  if (n < 3) return <int>[];

  final det = filtFilt(sosDet, xf);

  // 5-point derivative scaled by fs/8, then squaring.
  final d = List<double>.filled(n, 0.0);
  final factor = sampleRate / 8.0;
  for (var i = 2; i < n - 2; i++) {
    d[i] = (2.0 * det[i + 2] + det[i + 1] - det[i - 1] - 2.0 * det[i - 2]) * factor;
  }
  final sq = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    sq[i] = d[i] * d[i];
  }

  // Centered moving-window integration over about 150 ms.
  final half = (0.15 * sampleRate).toInt() ~/ 2;
  final c = List<double>.filled(n + 1, 0.0);
  var running = 0.0;
  for (var i = 0; i < n; i++) {
    running += sq[i];
    c[i + 1] = running;
  }
  final mwi = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    final lo = i - half > 0 ? i - half : 0;
    final hi = i + half + 1 < n ? i + half + 1 : n;
    mwi[i] = (c[hi] - c[lo]) / (hi - lo);
  }

  // Candidates: local maxima of the integrated signal.
  final candidates = <int>[];
  for (var i = 1; i < n - 1; i++) {
    if (mwi[i] > mwi[i - 1] && mwi[i] >= mwi[i + 1]) {
      candidates.add(i);
    }
  }

  final refr = (0.2 * sampleRate).toInt();

  // Initial estimates from the first 2 s of the integrated signal.
  final initEnd = 2 * sampleRate < n ? 2 * sampleRate : n;
  var initMax = mwi[0];
  var initSum = 0.0;
  for (var i = 0; i < initEnd; i++) {
    if (mwi[i] > initMax) initMax = mwi[i];
    initSum += mwi[i];
  }
  var spki = 0.5 * initMax;
  var npki = 0.5 * (initSum / initEnd);

  final acceptedPos = <int>[];
  final acceptedH = <double>[];
  final rejectedPos = <int>[];
  final rejectedH = <double>[];

  for (final ci in candidates) {
    final h = mwi[ci];
    final thr = npki + 0.25 * (spki - npki);
    if (h > thr) {
      if (acceptedPos.isNotEmpty && ci - acceptedPos.last < refr) {
        // Keep the larger one inside the refractory period.
        if (h > acceptedH.last) {
          acceptedPos[acceptedPos.length - 1] = ci;
          acceptedH[acceptedH.length - 1] = h;
        }
        continue;
      }
      // Search-back: a long gap means we probably missed a beat.
      if (acceptedPos.length > 8) {
        final start = acceptedPos.length - 9;
        var sum = 0.0;
        for (var i = start + 1; i < acceptedPos.length; i++) {
          sum += acceptedPos[i] - acceptedPos[i - 1];
        }
        final rr = sum / (acceptedPos.length - 1 - start);
        if (ci - acceptedPos.last > 1.66 * rr) {
          final loPos = acceptedPos.last + refr;
          final hiPos = ci - refr;
          var bestIdx = -1;
          var bestH = 0.0;
          for (var i = 0; i < rejectedPos.length; i++) {
            if (rejectedPos[i] >= loPos && rejectedPos[i] <= hiPos && rejectedH[i] > 0.5 * thr) {
              // Python's max(..., key=...) returns the FIRST maximum on ties.
              if (bestIdx < 0 || rejectedH[i] > bestH) {
                bestIdx = i;
                bestH = rejectedH[i];
              }
            }
          }
          if (bestIdx >= 0) {
            acceptedPos.add(rejectedPos[bestIdx]);
            acceptedH.add(rejectedH[bestIdx]);
          }
        }
      }
      acceptedPos.add(ci);
      acceptedH.add(h);
      spki = 0.125 * h + 0.875 * spki;
    } else {
      rejectedPos.add(ci);
      rejectedH.add(h);
      npki = 0.125 * h + 0.875 * npki;
    }
  }

  // Refine: largest deflection of the filtered signal near each detection.
  final w = (0.08 * sampleRate).toInt();
  final peaks = <int>[];
  for (final pos in acceptedPos) {
    final a = pos - w > 0 ? pos - w : 0;
    final b = pos + w + 1 < n ? pos + w + 1 : n;
    peaks.add(a + argMaxAbs(xf.sublist(a, b)));
  }

  // Remove duplicates created by refinement.
  final sorted = List<int>.from(peaks)..sort();
  final out = <int>[];
  for (final p in sorted) {
    if (out.isNotEmpty && p - out.last < refr) {
      if (xf[p].abs() > xf[out.last].abs()) {
        out[out.length - 1] = p;
      }
      continue;
    }
    out.add(p);
  }
  return out;
}
