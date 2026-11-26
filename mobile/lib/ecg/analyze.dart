/// The full portable v3.1 pipeline, ported 1:1 from `analyze_reference` in `src/portable.py`.
library;

import 'constants.dart' as ecg_constants;
import 'features_v3.dart';
import 'filter.dart';
import 'hgb_model.dart';
import 'resample.dart';
import 'rpeaks.dart';
import 'stats.dart';

/// Filter coefficients and decision weights from `ecg_config.json`.
class EcgConfig {
  EcgConfig({
    required this.sosMain,
    required this.sosDet,
    required this.weights,
    this.schemaVersion = 3,
    this.modelFile = 'ecg_model_v3.json',
    this.featureCount = ecg_constants.featureCount,
    this.sampleRate = ecg_constants.fs,
    this.preSamples = ecg_constants.pre,
    this.postSamples = ecg_constants.post,
  });

  final List<Biquad> sosMain;
  final List<Biquad> sosDet;
  final List<double> weights;
  final int schemaVersion;
  final String modelFile;
  final int featureCount;
  final int sampleRate;
  final int preSamples;
  final int postSamples;

  factory EcgConfig.fromJson(Map<String, dynamic> json) {
    return EcgConfig(
      sosMain: parseSos(json['sos_main'] as List<dynamic>),
      sosDet: parseSos(json['sos_det'] as List<dynamic>),
      weights: [
        for (final w in (json['decision_weights'] as List<dynamic>? ??
            ecg_constants.decisionWeights))
          (w as num).toDouble(),
      ],
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 3,
      modelFile: (json['model_file'] as String?) ?? 'ecg_model_v3.json',
      featureCount:
          (json['feature_count'] as num?)?.toInt() ?? ecg_constants.featureCount,
      sampleRate: (json['fs'] as num?)?.toInt() ?? ecg_constants.fs,
      preSamples: (json['pre'] as num?)?.toInt() ?? ecg_constants.pre,
      postSamples: (json['post'] as num?)?.toInt() ?? ecg_constants.post,
    );
  }
}

/// Everything the phone has to do, in the same order as the Python reference.
class EcgAnalyzer {
  EcgAnalyzer({required this.config, required this.model});

  final EcgConfig config;
  final HgbModel model;

  /// Run the whole pipeline on a raw signal sampled at [sourceFs].
  EcgResult analyze(List<double> raw, double sourceFs) {
    // Same order as analyze_reference: clean, resample (anti-aliased when the
    // source is faster than 360 Hz), band-pass, then detect.
    final rate = checkSampleRate(sourceFs);
    final sig = to360Hz(
      sanitizeSignal(raw, rate),
      rate,
      target: config.sampleRate,
    );
    final sigF = filtFilt(config.sosMain, sig);
    final peaks = detectRPeaks(sigF, config.sosDet, sampleRate: config.sampleRate);

    final beats = <List<double>>[];
    final rr = <List<int>>[];
    final prevRr = <int>[];
    final used = <int>[];

    for (var k = 1; k < peaks.length - 1; k++) {
      final p = peaks[k];
      if (p - config.preSamples < 0 || p + config.postSamples > sigF.length) {
        continue;
      }
      final prev = peaks[k] - peaks[k - 1];
      final next = peaks[k + 1] - peaks[k];
      beats.add(sigF.sublist(p - config.preSamples, p + config.postSamples));
      rr.add([prev, next]);
      prevRr.add(prev);
      used.add(p);
    }

    if (beats.isEmpty) {
      return EcgResult(
        signal: sigF,
        peaks: const <int>[],
        detectedPeaks: peaks,
        pred: const <int>[],
        proba: const <List<double>>[],
        scores: const <List<double>>[],
        sampleRate: config.sampleRate,
        p1: percentile(sigF, 1),
        p99: percentile(sigF, 99),
      );
    }

    final medRr = median([for (final r in prevRr) r.toDouble()]);
    final features = extractRecordingFeaturesV3(
      beats,
      rr,
      sampleRate: config.sampleRate.toDouble(),
    );

    final proba = <List<double>>[];
    final scores = <List<double>>[];
    final pred = <int>[];
    for (var i = 0; i < features.length; i++) {
      final p = model.predictProba(features[i]);
      final s = effectiveScores(p, config.weights);
      proba.add(p);
      scores.add(s);
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
      scores: scores,
      sampleRate: config.sampleRate,
      referenceMedianRr: medRr,
      p1: percentile(sigF, 1),
      p99: percentile(sigF, 99),
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
    required this.scores,
    required this.sampleRate,
    this.referenceMedianRr,
    this.p1 = 0.0,
    this.p99 = 0.0,
  });

  /// The filtered signal at 360 Hz.
  final List<double> signal;

  /// Positions of the analyzed beats (the R-peak inside each beat window).
  final List<int> peaks;

  /// All detected R-peaks, including the first and last that have no full window.
  final List<int> detectedPeaks;

  /// Predicted class index per analyzed beat.
  final List<int> pred;

  /// Unweighted class probabilities per analyzed beat.
  final List<List<double>> proba;

  /// Normalized decision-weighted model scores per analyzed beat.
  final List<List<double>> scores;

  final int sampleRate;

  /// The recording-level median R-R (in samples) over analyzed beats.
  final double? referenceMedianRr;

  /// 1st and 99th percentile of the filtered signal.
  final double p1;
  final double p99;

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
