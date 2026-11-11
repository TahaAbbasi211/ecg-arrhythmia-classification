/// The full portable pipeline, ported 1:1 from `analyze_reference` in `src/portable.py`.
library;

import 'constants.dart';
import 'features.dart';
import 'filter.dart';
import 'forest.dart';
import 'resample.dart';
import 'rpeaks.dart';
import 'stats.dart';

/// Filter coefficients and decision weights from `ecg_config.json`.
class EcgConfig {
  EcgConfig({
    required this.sosMain,
    required this.sosDet,
    required this.weights,
    this.sampleRate = fs,
    this.preSamples = pre,
    this.postSamples = post,
  });

  final List<Biquad> sosMain;
  final List<Biquad> sosDet;
  final List<double> weights;
  final int sampleRate;
  final int preSamples;
  final int postSamples;

  factory EcgConfig.fromJson(Map<String, dynamic> json) {
    return EcgConfig(
      sosMain: parseSos(json['sos_main'] as List<dynamic>),
      sosDet: parseSos(json['sos_det'] as List<dynamic>),
      weights: [
        for (final w in (json['decision_weights'] as List<dynamic>? ??
            decisionWeights))
          (w as num).toDouble(),
      ],
      sampleRate: (json['fs'] as num?)?.toInt() ?? fs,
      preSamples: (json['pre'] as num?)?.toInt() ?? pre,
      postSamples: (json['post'] as num?)?.toInt() ?? post,
    );
  }
}

/// Everything the phone has to do, in the same order as the Python reference.
class EcgAnalyzer {
  EcgAnalyzer({required this.config, required this.forest});

  final EcgConfig config;
  final Forest forest;

  /// Run the whole pipeline on a raw signal sampled at [sourceFs].
  EcgResult analyze(List<double> raw, double sourceFs) {
    final sig = resampleLinear(raw, sourceFs, target: config.sampleRate);
    final sigF = filtFilt(config.sosMain, sig);
    final peaks = detectRPeaks(sigF, config.sosDet, sampleRate: config.sampleRate);

    final beats = <List<double>>[];
    final prevRr = <int>[];
    final nextRr = <int>[];
    final used = <int>[];

    for (var k = 1; k < peaks.length - 1; k++) {
      final p = peaks[k];
      if (p - config.preSamples < 0 || p + config.postSamples > sigF.length) {
        continue;
      }
      beats.add(sigF.sublist(p - config.preSamples, p + config.postSamples));
      prevRr.add(peaks[k] - peaks[k - 1]);
      nextRr.add(peaks[k + 1] - peaks[k]);
      used.add(p);
    }

    if (beats.isEmpty) {
      return EcgResult(
        signal: sigF,
        peaks: const <int>[],
        detectedPeaks: peaks,
        pred: const <int>[],
        proba: const <List<double>>[],
        sampleRate: config.sampleRate,
      );
    }

    // Recording-level median R-R over the beats that are actually analyzed.
    final medRr = median([for (final r in prevRr) r.toDouble()]);

    final proba = <List<double>>[];
    final pred = <int>[];
    for (var i = 0; i < beats.length; i++) {
      final features = beatFeatures(beats[i], prevRr[i], nextRr[i], medRr);
      final p = forest.predictProba(features);
      proba.add(p);
      // argmax of (proba * decision_weights), first index on ties.
      final weighted = <double>[
        for (var c = 0; c < p.length; c++) p[c] * config.weights[c],
      ];
      pred.add(argMax(weighted));
    }

    return EcgResult(
      signal: sigF,
      peaks: used,
      detectedPeaks: peaks,
      pred: pred,
      proba: proba,
      sampleRate: config.sampleRate,
      referenceMedianRr: medRr,
    );
  }
}

/// Output of [EcgAnalyzer.analyze].
class EcgResult {
  EcgResult({
    required this.signal,
    required this.peaks,
    required this.detectedPeaks,
    required this.pred,
    required this.proba,
    required this.sampleRate,
    this.referenceMedianRr,
  });

  /// The filtered signal at 360 Hz.
  final List<double> signal;

  /// Positions of the analyzed beats (the R-peak inside each beat window).
  final List<int> peaks;

  /// All detected R-peaks, including the first and last that have no full window.
  final List<int> detectedPeaks;

  /// Predicted class index per analyzed beat.
  final List<int> pred;

  /// Class probabilities per analyzed beat.
  final List<List<double>> proba;

  final int sampleRate;

  /// The recording-level median R-R (in samples) the reference used for the
  /// features. Null when no beat was analyzed.
  final double? referenceMedianRr;

  int get beatCount => pred.length;

  /// Median R-R interval in samples, or null when there are no beats.
  double? get medianRr {
    if (peaks.length < 2) return null;
    final rr = <double>[];
    for (var i = 1; i < peaks.length; i++) {
      rr.add((peaks[i] - peaks[i - 1]).toDouble());
    }
    return median(rr);
  }

  /// Heart rate in bpm from the median R-R interval.
  double? get heartRate {
    final rr = medianRr;
    if (rr == null || rr <= 0) return null;
    return 60.0 * sampleRate / rr;
  }

  int countOf(int classIndex) => pred.where((p) => p == classIndex).length;
}
