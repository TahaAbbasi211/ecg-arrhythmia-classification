import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ecg_beat_classifier/ecg/analyze.dart';
import 'package:ecg_beat_classifier/ecg/features.dart';
import 'package:ecg_beat_classifier/ecg/filter.dart';
import 'package:ecg_beat_classifier/ecg/forest.dart';
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
  final forest = Forest.fromJson(_loadJson('../export/ecg_forest.json'));

  test('forest loads 50 trees with 4 classes', () {
    expect(forest.trees.length, 50);
    expect(forest.nClasses, 4);
  });

  final cases = (vectors['cases'] as Map<String, dynamic>);

  for (final entry in cases.entries) {
    final name = entry.key;
    final c = entry.value as Map<String, dynamic>;
    final raw = _doubles(c['raw']);
    final filtered = _doubles(c['filtered']);
    final detected = [for (final v in c['detected_peaks'] as List<dynamic>) (v as num).toInt()];
    final used = [for (final v in c['used_peaks'] as List<dynamic>) (v as num).toInt()];
    final pred = [for (final v in c['pred'] as List<dynamic>) (v as num).toInt()];
    final proba = [
      for (final row in c['proba'] as List<dynamic>) _doubles(row),
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

      test('beatFeatures match within 1e-6 relative', () {
        final beatTests = c['beat_tests'] as List<dynamic>;
        for (var b = 0; b < beatTests.length; b++) {
          final bt = beatTests[b] as Map<String, dynamic>;
          final beat = _doubles(bt['beat']);
          final expected = _doubles(bt['features']);
          final got = beatFeatures(
            beat,
            (bt['prev_rr'] as num).toInt(),
            (bt['next_rr'] as num).toInt(),
            (bt['median_rr'] as num).toDouble(),
          );
          expect(got.length, 57);
          for (var i = 0; i < expected.length; i++) {
            final tol = 1e-6 + 1e-6 * expected[i].abs();
            expect((got[i] - expected[i]).abs(), lessThanOrEqualTo(tol),
                reason: 'beat $b feature $i: dart ${got[i]}, '
                    'python ${expected[i]}, tol $tol');
          }
        }
      });

      test('Forest.predictProba matches within 1e-5', () {
        final beatTests = c['beat_tests'] as List<dynamic>;
        for (var b = 0; b < beatTests.length; b++) {
          final bt = beatTests[b] as Map<String, dynamic>;
          final features = _doubles(bt['features']);
          final expected = _doubles(bt['proba']);
          final got = forest.predictProba(features);
          for (var i = 0; i < 4; i++) {
            expect((got[i] - expected[i]).abs(), lessThanOrEqualTo(1e-5),
                reason: 'beat $b class $i: dart ${got[i]}, python ${expected[i]}');
          }
        }
      });

      test('analyze matches used_peaks, pred and proba', () {
        final analyzer = EcgAnalyzer(config: config, forest: forest);
        final result = analyzer.analyze(raw, 360);
        expect(result.peaks, used, reason: 'used_peaks');
        expect(result.pred, pred, reason: 'pred');
        expect(result.proba.length, proba.length);
        for (var b = 0; b < proba.length; b++) {
          for (var i = 0; i < 4; i++) {
            expect((result.proba[b][i] - proba[b][i]).abs(),
                lessThanOrEqualTo(1e-5),
                reason: 'beat $b class $i: dart ${result.proba[b][i]}, '
                    'python ${proba[b][i]}');
          }
        }
      });
    });
  }

  test('analyze() timing on a 30-minute signal', () {
    final c = cases['record_200_100s'] as Map<String, dynamic>;
    final raw = _doubles(c['raw']);
    const targetSamples = 650000;
    final long = List<double>.filled(targetSamples, 0.0);
    for (var i = 0; i < targetSamples; i++) {
      long[i] = raw[i % raw.length];
    }
    final analyzer = EcgAnalyzer(config: config, forest: forest);
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
