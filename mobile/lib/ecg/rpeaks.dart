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

  // Robust initial thresholds. Half of the first 2 s peak would let one 50 mV
  // spike near the start raise the threshold so far that every real beat is
  // missed. The median of the 2 s block maxima over the first 8 s ignores such
  // an outlier, and the noise peak is a median too.
  final initEnd = 8 * sampleRate < n ? 8 * sampleRate : n;
  final block = 2 * sampleRate;
  final blockMaxima = <double>[];
  for (var start = 0; start < initEnd; start += block) {
    final stop = start + block < initEnd ? start + block : initEnd;
    var blockMax = mwi[start];
    for (var i = start + 1; i < stop; i++) {
      if (mwi[i] > blockMax) blockMax = mwi[i];
    }
    if (blockMax > 0) blockMaxima.add(blockMax);
  }
  var spki = blockMaxima.isEmpty ? 0.0 : median(blockMaxima);
  var npki = initEnd > 0 ? median(mwi.sublist(0, initEnd)) : 0.0;
  if (npki > spki) npki = 0.5 * spki;

  final acceptedPos = <int>[];
  final acceptedH = <double>[];
  final rejectedPos = <int>[];
  final rejectedH = <double>[];
  // Forward pointer into the rejected candidates; keeps search-back O(N).
  var rj = 0;

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
          // loPos and hiPos only ever move forward, so a single pointer walks
          // the rejected list once instead of rescanning it for every beat.
          while (rj < rejectedPos.length && rejectedPos[rj] < loPos) {
            rj++;
          }
          var bestIdx = -1;
          var bestH = 0.0;
          var j = rj;
          while (j < rejectedPos.length && rejectedPos[j] <= hiPos) {
            if (rejectedH[j] > 0.5 * thr && (bestIdx < 0 || rejectedH[j] > bestH)) {
              bestIdx = j;
              bestH = rejectedH[j];
            }
            j++;
          }
          if (bestIdx >= 0) {
            acceptedPos.add(rejectedPos[bestIdx]);
            acceptedH.add(rejectedH[bestIdx]);
          }
        }
      }
      acceptedPos.add(ci);
      acceptedH.add(h);
      // Cap the jump: one noisy peak may not quadruple the signal estimate.
      spki = 0.125 * (spki > 0 ? (h < 4.0 * spki ? h : 4.0 * spki) : h) + 0.875 * spki;
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
