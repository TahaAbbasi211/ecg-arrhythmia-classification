import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ecg_beat_classifier/ecg/analyze.dart';
import 'package:ecg_beat_classifier/ecg/constants.dart';
import 'package:ecg_beat_classifier/ecg/features_v3.dart';
import 'package:ecg_beat_classifier/ecg/filter.dart';
import 'package:ecg_beat_classifier/ecg/hgb_model.dart';
import 'package:ecg_beat_classifier/ecg/resample.dart';
import 'package:ecg_beat_classifier/ecg/rpeaks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden vectors produced by the Python reference (`src/portable.py`).
///
/// Read from the repo, never bundled into the app.
Map<String, dynamic> _loadJson(String relative) {
  final file = File(relative);
  if (!file.existsSync()) {
    fail('Missing golden file: ${file.absolute.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<double> _doubles(dynamic raw) =>
    [for (final v in raw as List<dynamic>) (v as num).toDouble()];

void main() {
  // Loaded synchronously: the case list is needed while building the groups.
  final vectors = _loadJson('../export/test_vectors.json');
  final config = EcgConfig.fromJson(_loadJson('../export/ecg_config.json'));
  final model = HgbModel.fromJson(_loadJson('../export/ecg_model_v3.json'));

  test('v3.1 HGB model loads 65 iterations x 3 classes over 84 features', () {
    expect(model.schemaVersion, 3);
    expect(model.kind, 'hgb');
    expect(model.classes, [0, 1, 2]);
    expect(model.nClasses, 4);
    expect(model.featureCount, 84);
    expect(model.iterations.length, 65);
    expect(model.iterations.every((it) => it.length == 3), isTrue);
    expect(config.schemaVersion, 3);
    expect(config.modelFile, 'ecg_model_v3.json');
    expect(config.featureCount, 84);
    expect(config.weights, [1.0, 0.25, 0.5, 0.0]);
  });

  group('HgbModel guards and effectiveScores', () {
    test('predictProba rejects NaN, Inf, and wrong feature length', () {
      final valid = List<double>.filled(84, 0.0);
      expect(model.predictProba(valid).length, 4);

      for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
        final feats = List<double>.filled(84, 0.0);
        feats[7] = bad;
        expect(() => model.predictProba(feats), throwsArgumentError);
      }

      expect(
        () => model.predictProba(List<double>.filled(57, 0.0)),
        throwsArgumentError,
      );
    });

    test('effectiveScores normalizes weighted scores and handles zero sum', () {
      final p = [0.6, 0.3, 0.1, 0.0];
      final s = effectiveScores(p, decisionWeights);
      expect(s.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(s[0], closeTo(0.6 / 0.725, 1e-12));
      expect(s[1], closeTo(0.075 / 0.725, 1e-12));
      expect(s[2], closeTo(0.05 / 0.725, 1e-12));
      expect(s[3], 0.0);

      final zeroFallback = effectiveScores(p, const [0.0, 0.0, 0.0, 0.0]);
      expect(zeroFallback, p);
    });
  });

  group('resampling parity with src/portable.py', () {
    final parity = _loadJson('../export/resample_parity.json');

    for (final entry in parity['cases'] as List<dynamic>) {
      final c = entry as Map<String, dynamic>;
      final rate = (c['fs'] as num).toDouble();

      test('${c['fs']} Hz downsamples like the reference', () {
        final raw = _doubles(c['raw']);
        final expected = _doubles(c['expected']);
        final got = to360Hz(raw, rate);
        expect(got.length, expected.length);
        var maxDiff = 0.0;
        var worstAt = -1;
        for (var i = 0; i < got.length; i++) {
          final d = (got[i] - expected[i]).abs();
          if (d > maxDiff) {
            maxDiff = d;
            worstAt = i;
          }
        }
        expect(maxDiff, lessThanOrEqualTo(1e-8),
            reason: 'max |diff| = $maxDiff at sample $worstAt '
                '(dart ${got[worstAt]}, python ${expected[worstAt]})');
      });
    }
  });

  group('input hygiene and short-signal rpeaks', () {
    test('a bad sampling rate is rejected', () {
      expect(() => to360Hz(const [1.0, 2.0, 3.0], 0),
          throwsA(isA<SignalException>()));
      expect(() => to360Hz(const [1.0, 2.0, 3.0], double.nan),
          throwsA(isA<SignalException>()));
    });

    test('scattered NaN and Inf are interpolated', () {
      final x = [for (var i = 0; i < 1000; i++) i.toDouble()];
      x[10] = double.nan;
      x[500] = double.infinity;
      final out = sanitizeSignal(x, 360);
      expect(out.every((v) => v.isFinite), isTrue);
      expect(out[10], closeTo(10.0, 1e-9));
      expect(out[500], closeTo(500.0, 1e-9));
    });

    test('a long corrupt gap is rejected', () {
      final x = List<double>.filled(36000, 0.0);
      for (var i = 1000; i < 1300; i++) {
        x[i] = double.nan;
      }
      expect(() => sanitizeSignal(x, 360), throwsA(isA<SignalException>()));
    });

    test('detectRPeaks returns empty when fewer than 5 samples', () {
      for (var len = 0; len < 5; len++) {
        expect(detectRPeaks(List<double>.filled(len, 0.0), config.sosDet), isEmpty);
      }
    });
  });

  final cases = vectors['cases'] as Map<String, dynamic>;

  for (final entry in cases.entries) {
    final name = entry.key;
    final c = entry.value as Map<String, dynamic>;
    final raw = _doubles(c['raw']);
    final filtered = _doubles(c['filtered']);
    final detected = [
      for (final v in c['detected_peaks'] as List<dynamic>) (v as num).toInt(),
    ];
    final used = [
      for (final v in c['used_peaks'] as List<dynamic>) (v as num).toInt(),
    ];
    final pred = [
      for (final v in c['pred'] as List<dynamic>) (v as num).toInt(),
    ];
    final proba = [
      for (final row in c['proba'] as List<dynamic>) _doubles(row),
    ];
    final scores = [
      for (final row in c['scores'] as List<dynamic>) _doubles(row),
    ];
    final featIndices = [
      for (final v in c['feature_indices'] as List<dynamic>) (v as num).toInt(),
    ];
    final expectedFeats = [
      for (final row in c['features'] as List<dynamic>) _doubles(row),
    ];
    final expectedFeatProba = [
      for (final row in c['feature_proba'] as List<dynamic>) _doubles(row),
    ];
    final expectedFeatScores = [
      for (final row in c['feature_scores'] as List<dynamic>) _doubles(row),
    ];

    group(name, () {
      test('filtFilt matches the reference within 1e-6', () {
        final got = filtFilt(config.sosMain, raw);
        expect(got.length, filtered.length);
        var maxDiff = 0.0;
        var worstAt = -1;
        for (var i = 0; i < got.length; i++) {
          final d = (got[i] - filtered[i]).abs();
          if (d > maxDiff) {
            maxDiff = d;
            worstAt = i;
          }
        }
        expect(maxDiff, lessThanOrEqualTo(1e-6),
            reason: 'max |diff| = $maxDiff at sample $worstAt '
                '(dart ${got[worstAt]}, python ${filtered[worstAt]})');
      });

      test('detectRPeaks matches exactly', () {
        final got = detectRPeaks(filtered, config.sosDet);
        expect(got, detected);
      });

      test('extractRecordingFeaturesV3 84 features match within 1e-10', () {
        final pos = <int, int>{
          for (var k = 0; k < detected.length; k++) detected[k]: k,
        };
        final beats = <List<double>>[];
        final rr = <List<int>>[];
        for (final p in used) {
          final k = pos[p]!;
          beats.add(filtered.sublist(p - pre, p + post));
          rr.add([detected[k] - detected[k - 1], detected[k + 1] - detected[k]]);
        }
        final gotAll = extractRecordingFeaturesV3(beats, rr, sampleRate: 360.0);
        expect(gotAll.length, used.length);

        var maxDiff = 0.0;
        var worstBeat = -1;
        var worstFeat = -1;
        for (var idxPos = 0; idxPos < featIndices.length; idxPos++) {
          final beatIdx = featIndices[idxPos];
          final got = gotAll[beatIdx];
          final expected = expectedFeats[idxPos];
          expect(got.length, 84);
          for (var j = 0; j < 84; j++) {
            final d = (got[j] - expected[j]).abs();
            if (d > maxDiff) {
              maxDiff = d;
              worstBeat = beatIdx;
              worstFeat = j;
            }
          }
        }
        expect(maxDiff, lessThan(1e-10),
            reason: 'max feature |diff| = $maxDiff at beat $worstBeat feat $worstFeat');
      });

      test('HgbModel.predictProba & effectiveScores match within 1e-6', () {
        for (var idxPos = 0; idxPos < expectedFeats.length; idxPos++) {
          final gotProba = model.predictProba(expectedFeats[idxPos]);
          final gotScore = effectiveScores(gotProba, config.weights);
          for (var cIdx = 0; cIdx < 4; cIdx++) {
            expect(
              (gotProba[cIdx] - expectedFeatProba[idxPos][cIdx]).abs(),
              lessThanOrEqualTo(1e-6),
              reason: 'key beat $idxPos class $cIdx proba',
            );
            expect(
              (gotScore[cIdx] - expectedFeatScores[idxPos][cIdx]).abs(),
              lessThanOrEqualTo(1e-6),
              reason: 'key beat $idxPos class $cIdx score',
            );
          }
        }
      });

      test('analyze matches used_peaks, pred, proba, and scores', () {
        final analyzer = EcgAnalyzer(config: config, model: model);
        final result = analyzer.analyze(raw, 360);
        expect(result.peaks, used, reason: 'used_peaks');
        expect(result.pred, pred, reason: 'pred');
        expect(result.proba.length, proba.length);
        expect(result.scores.length, scores.length);
        for (var b = 0; b < proba.length; b++) {
          for (var i = 0; i < 4; i++) {
            expect((result.proba[b][i] - proba[b][i]).abs(),
                lessThanOrEqualTo(1e-6),
                reason: 'beat $b class $i: dart ${result.proba[b][i]}, '
                    'python ${proba[b][i]}');
            expect((result.scores[b][i] - scores[b][i]).abs(),
                lessThanOrEqualTo(1e-6),
                reason: 'beat $b class $i score: dart ${result.scores[b][i]}, '
                    'python ${scores[b][i]}');
          }
        }
      });
    });
  }

  test('end-to-end scale invariance across Volts (0.001x), mV (1x), uV (1000x)',
      () {
    final scaleCase = vectors['scale_invariance'] as Map<String, dynamic>;
    final baseCase = cases[scaleCase['base_case']] as Map<String, dynamic>;
    final raw = _doubles(baseCase['raw']);
    final expectedPeaks = [
      for (final v in scaleCase['used_peaks'] as List<dynamic>) (v as num).toInt(),
    ];
    final expectedPred = [
      for (final v in scaleCase['pred'] as List<dynamic>) (v as num).toInt(),
    ];
    final expectedProba = [
      for (final row in scaleCase['proba'] as List<dynamic>) _doubles(row),
    ];
    final expectedScores = [
      for (final row in scaleCase['scores'] as List<dynamic>) _doubles(row),
    ];

    final analyzer = EcgAnalyzer(config: config, model: model);
    for (final factor in _doubles(scaleCase['scales'])) {
      final scaled = [for (final v in raw) v * factor];
      final res = analyzer.analyze(scaled, 360);
      expect(res.peaks, expectedPeaks, reason: 'peaks at scale $factor');
      expect(res.pred, expectedPred, reason: 'pred at scale $factor');
      for (var b = 0; b < expectedProba.length; b++) {
        for (var cIdx = 0; cIdx < 4; cIdx++) {
          expect(
            (res.proba[b][cIdx] - expectedProba[b][cIdx]).abs(),
            lessThanOrEqualTo(1e-6),
            reason: 'scale $factor beat $b class $cIdx proba',
          );
          expect(
            (res.scores[b][cIdx] - expectedScores[b][cIdx]).abs(),
            lessThanOrEqualTo(1e-6),
            reason: 'scale $factor beat $b class $cIdx score',
          );
        }
      }
    }
  });

  test('analyze() timing on a 30-minute signal', () {
    final c = cases['record_200_100s'] as Map<String, dynamic>;
    final raw = _doubles(c['raw']);
    const targetSamples = 650000;
    final long = List<double>.filled(targetSamples, 0.0);
    for (var i = 0; i < targetSamples; i++) {
      long[i] = raw[i % raw.length];
    }
    final analyzer = EcgAnalyzer(config: config, model: model);
    final sw = Stopwatch()..start();
    final result = analyzer.analyze(long, 360);
    sw.stop();
    final seconds = sw.elapsedMilliseconds / 1000.0;
    // ignore: avoid_print
    print('analyze() on ${long.length} samples (${(long.length / 360 / 60).toStringAsFixed(1)} min): '
        '${seconds.toStringAsFixed(2)} s, ${result.beatCount} beats');
    expect(result.beatCount, greaterThan(0));
    expect(seconds, lessThan(120), reason: 'analysis must stay usable on a phone');
    // Sanity: the tiled signal must still be finite everywhere.
    expect(result.signal.every((v) => v.isFinite), isTrue);
    expect(math.max(1, result.signal.length), result.signal.length);
  });
}
