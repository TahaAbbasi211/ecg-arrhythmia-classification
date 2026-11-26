/// 84 scale-invariant, patient-template, and local-rhythm ECG beat features (v3),
/// ported 1:1 in float64 (`double`) from `src/features_v3.py`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'stats.dart';

/// Linear-interpolation quantile on a pre-sorted 1D sequence (`_quantile_sorted`).
double quantileSorted(List<double> sortedVals, double q) {
  final m = sortedVals.length;
  if (m == 0) return 0.0;
  if (m == 1) return sortedVals[0];
  final pos = q * (m - 1);
  final lo = pos.floor();
  final hi = math.min(lo + 1, m - 1);
  final frac = pos - lo;
  return sortedVals[lo] * (1.0 - frac) + sortedVals[hi] * frac;
}

/// Compute robust recording amplitude scale and scale-normalized centered beats.
({double recScale, List<Float64List> xRec}) computeRecordingScale(
  List<List<double>> beats,
) {
  final n = beats.length;
  if (n == 0) {
    return (recScale: 1.0, xRec: const <Float64List>[]);
  }
  final centered = <Float64List>[];
  final p2pRaw = List<double>.filled(n, 0.0);

  for (var i = 0; i < n; i++) {
    final beat = beats[i];
    if (beat.length != beatLength) {
      throw ArgumentError(
        'expected beat length $beatLength, got ${beat.length} at beat $i',
      );
    }
    final med = median(beat);
    final row = Float64List(beatLength);
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (var j = 0; j < beatLength; j++) {
      final v = beat[j] - med;
      row[j] = v;
      if (v > hi) hi = v;
      if (v < lo) lo = v;
    }
    centered.add(row);
    p2pRaw[i] = hi - lo;
  }

  final medP2p = median(p2pRaw);
  final recScale = medP2p > featureEps ? medP2p : featureEps;
  for (var i = 0; i < n; i++) {
    final row = centered[i];
    for (var j = 0; j < beatLength; j++) {
      row[j] = row[j] / recScale;
    }
  }
  return (recScale: recScale, xRec: centered);
}

/// Build an element-wise median beat template across a recording's normalized beats.
Float64List computeRecordingTemplate(List<List<double>> xRec) {
  final n = xRec.length;
  final template = Float64List(beatLength);
  if (n == 0) return template;

  final col = List<double>.filled(n, 0.0);
  for (var j = 0; j < beatLength; j++) {
    for (var i = 0; i < n; i++) {
      col[i] = xRec[i][j];
    }
    template[j] = median(col);
  }
  return template;
}

/// Return (prev_rr + next_rr) / max(2 * local_med_rr, featureEps).
double computeCompensatoryPauseRatio(
  double prevRr,
  double nextRr,
  double localMedRr,
) {
  final denom = math.max(2.0 * localMedRr, featureEps);
  return (prevRr + nextRr) / denom;
}

void _writeLocalRhythmRow(
  Float64List out,
  int i,
  List<double> prevRr,
  List<double> nextRr,
  double sampleRate,
  int halfWin,
) {
  final n = prevRr.length;
  final lo = math.max(0, i - halfWin);
  final hi = math.min(n, i + halfWin + 1);
  final winSorted = <double>[
    for (var j = lo; j < hi; j++) prevRr[j],
  ]..sort();

  final localMed = quantileSorted(winSorted, 0.5);
  final localIqr =
      quantileSorted(winSorted, 0.75) - quantileSorted(winSorted, 0.25);

  final pI = prevRr[i];
  final nI = nextRr[i];
  final p2I = i > 0 ? prevRr[i - 1] : pI;
  final n2I = i + 1 < n ? nextRr[i + 1] : nI;
  final safeMed = math.max(localMed, featureEps);

  out[0] = pI / sampleRate;
  out[1] = nI / sampleRate;
  out[2] = localMed / sampleRate;
  out[3] = pI / safeMed;
  out[4] = nI / safeMed;
  out[5] = computeCompensatoryPauseRatio(pI, nI, localMed);
  out[6] = pI / math.max(nI, featureEps);
  out[7] = (nI - pI) / math.max(pI + nI, featureEps);
  out[8] = pI / math.max(p2I, featureEps);
  out[9] = nI / math.max(n2I, featureEps);
  out[10] = p2I / safeMed;
  out[11] = n2I / safeMed;
  out[12] = localIqr / safeMed;
  out[13] = (pI - localMed) / math.max(localIqr, math.max(0.05 * localMed, featureEps));
}

void _writeMorphRow(Float64List out, Float64List x) {
  var peak = x[0];
  var trough = x[0];
  var absMax = x[0].abs();
  var tPeakIdx = 0;
  var tTroughIdx = 0;
  var energy = 0.0;
  var area = 0.0;
  var sum = 0.0;

  for (var j = 0; j < beatLength; j++) {
    final v = x[j];
    if (v > peak) {
      peak = v;
      tPeakIdx = j;
    }
    if (v < trough) {
      trough = v;
      tTroughIdx = j;
    }
    final av = v.abs();
    if (av > absMax) absMax = av;
    energy += v * v;
    area += av;
    sum += v;
  }

  final p2p = peak - trough;
  final ampR = x[rPos];
  final tPeak = (tPeakIdx - rPos).toDouble();
  final tTrough = (tTroughIdx - rPos).toDouble();

  final thr = 0.3 * absMax;
  var width = 0;
  final wLo = rPos - 40;
  final wHi = rPos + 40;
  for (var j = wLo; j < wHi; j++) {
    if (x[j].abs() > thr) width++;
  }

  final mean = sum / beatLength;
  var m2 = 0.0;
  var m3 = 0.0;
  var m4 = 0.0;
  for (var j = 0; j < beatLength; j++) {
    final dev = x[j] - mean;
    final d2 = dev * dev;
    m2 += d2;
    m3 += d2 * dev;
    m4 += d2 * d2;
  }
  m2 /= beatLength;
  m3 /= beatLength;
  m4 /= beatLength;

  final sd = math.sqrt(m2);
  double sk;
  double ku;
  if (m2 <= 1e-12) {
    sk = 0.0;
    ku = 0.0;
  } else {
    sk = m3 / math.pow(m2, 1.5);
    ku = m4 / (m2 * m2) - 3.0;
  }

  out[14] = ampR;
  out[15] = peak;
  out[16] = trough;
  out[17] = p2p;
  out[18] = tPeak;
  out[19] = tTrough;
  out[20] = width.toDouble();
  out[21] = energy;
  out[22] = area;
  out[23] = sd;
  out[24] = sk;
  out[25] = ku;

  final shapeDen = p2p + featureEps;
  for (var k = 0; k < 40; k++) {
    out[26 + k] = x[k * 5] / shapeDen;
  }
}

class _TplSegmentStats {
  _TplSegmentStats(Float64List tpl, this.start, this.end)
      : len = end - start,
        tplSlice = Float64List(end - start),
        db = Float64List(end - start) {
    var sum = 0.0;
    for (var k = 0; k < len; k++) {
      final v = tpl[start + k];
      tplSlice[k] = v;
      sum += v;
    }
    final mean = sum / len;
    var vSum = 0.0;
    for (var k = 0; k < len; k++) {
      final d = tplSlice[k] - mean;
      db[k] = d;
      vSum += d * d;
    }
    vb = vSum;
  }

  final int start;
  final int end;
  final int len;
  final Float64List tplSlice;
  final Float64List db;
  late final double vb;

  ({double corr, double rms}) compare(Float64List x) {
    var sumDiffSq = 0.0;
    var sumSeg = 0.0;
    for (var k = 0; k < len; k++) {
      final v = x[start + k];
      final d = v - tplSlice[k];
      sumDiffSq += d * d;
      sumSeg += v;
    }
    final rms = math.sqrt(sumDiffSq / len);
    final meanSeg = sumSeg / len;
    var va = 0.0;
    var dot = 0.0;
    for (var k = 0; k < len; k++) {
      final da = x[start + k] - meanSeg;
      va += da * da;
      dot += da * db[k];
    }
    final denom = math.sqrt(va * vb);
    final corr = denom > 1e-12 ? (dot / denom).clamp(-1.0, 1.0) : 0.0;
    return (corr: corr, rms: rms);
  }
}

/// Extract the 84-column v3 feature matrix for a single recording/clip.
///
/// Mirrors `extract_recording_features_v3` in `src/features_v3.py` 1:1.
List<Float64List> extractRecordingFeaturesV3(
  List<List<double>> beats,
  List<List<num>> rr, {
  double sampleRate = 360.0,
}) {
  final n = beats.length;
  if (rr.length != n) {
    throw ArgumentError('expected rr length $n, got ${rr.length}');
  }
  if (n == 0) return const <Float64List>[];

  final prevRr = List<double>.filled(n, 0.0);
  final nextRr = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    if (rr[i].length != 2) {
      throw ArgumentError('expected rr[$i] length 2, got ${rr[i].length}');
    }
    final p = rr[i][0].toDouble();
    final nx = rr[i][1].toDouble();
    prevRr[i] = p > 0.0 ? p : 0.0;
    nextRr[i] = nx > 0.0 ? nx : 0.0;
  }

  final (:recScale, :xRec) = computeRecordingScale(beats);
  final _ = recScale;
  final template = computeRecordingTemplate(xRec);

  final segPStats = _TplSegmentStats(template, pStart, pEnd);
  final segQrsStats = _TplSegmentStats(template, qrsStart, qrsEnd);
  final segTStats = _TplSegmentStats(template, tStart, tEnd);
  final segFullStats = _TplSegmentStats(template, 0, beatLength);

  var tplPMax = template[pStart];
  var tplPMin = template[pStart];
  for (var j = pStart + 1; j < pEnd; j++) {
    if (template[j] > tplPMax) tplPMax = template[j];
    if (template[j] < tplPMin) tplPMin = template[j];
  }
  var tplTMax = template[tStart];
  for (var j = tStart + 1; j < tEnd; j++) {
    if (template[j] > tplTMax) tplTMax = template[j];
  }

  final out = <Float64List>[];
  for (var i = 0; i < n; i++) {
    final row = Float64List(featureCount);
    final x = xRec[i];

    _writeLocalRhythmRow(row, i, prevRr, nextRr, sampleRate, localRrHalfWin);
    _writeMorphRow(row, x);

    final pRes = segPStats.compare(x);
    final qrsRes = segQrsStats.compare(x);
    final tRes = segTStats.compare(x);
    final fullRes = segFullStats.compare(x);

    row[66] = pRes.corr;
    row[67] = pRes.rms;
    row[68] = qrsRes.corr;
    row[69] = qrsRes.rms;
    row[70] = tRes.corr;
    row[71] = tRes.rms;
    row[72] = fullRes.corr;
    row[73] = fullRes.rms;
    row[74] = qrsRes.corr - pRes.corr;

    var eP = 0.0;
    var pMax = x[pStart];
    var pMin = x[pStart];
    var pArgMax = 0;
    for (var j = pStart; j < pEnd; j++) {
      final v = x[j];
      eP += v * v;
      if (v > pMax) {
        pMax = v;
        pArgMax = j - pStart;
      }
      if (v < pMin) {
        pMin = v;
      }
    }

    var eQrs = 0.0;
    for (var j = qrsStart; j < qrsEnd; j++) {
      final v = x[j];
      eQrs += v * v;
    }

    var eT = 0.0;
    var tMax = x[tStart];
    for (var j = tStart; j < tEnd; j++) {
      final v = x[j];
      eT += v * v;
      if (v > tMax) tMax = v;
    }

    row[75] = eP / (eQrs + featureEps);
    row[76] = eT / (eQrs + featureEps);
    row[77] = pMax;
    row[78] = pMin;
    row[79] = (pStart + pArgMax - rPos).toDouble();
    row[80] = pMax - tplPMax;
    row[81] = pMin - tplPMin;
    row[82] = tMax;
    row[83] = tMax - tplTMax;

    out.add(row);
  }
  return out;
}
