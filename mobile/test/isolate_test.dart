import 'dart:io';

import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/data/signal_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end check of the isolate path the app actually uses.
void main() {
  test('analysis runs in an isolate and matches the v3.1 reference counts',
      () async {
    final configJson = File('assets/ecg_config.json').readAsStringSync();
    final modelJson = File('assets/ecg_model_v3.json').readAsStringSync();
    final raw = parseSignalText(
      File('assets/samples/record_200.csv').readAsStringSync(),
    ).values;

    final payload = await analyzeInIsolate(
      raw: raw,
      sourceFs: 360,
      configJson: configJson,
      modelJson: modelJson,
    );

    // Reference values for the bundled 60 s record 200 CSV under v3.1.
    expect(payload.beatCount, 81);
    expect(payload.countOf(0), 37);
    expect(payload.countOf(1), 0);
    expect(payload.countOf(2), 44);
    expect(payload.heartRate, isNotNull);
    expect(payload.heartRate!, closeTo(89.26, 0.05));
    expect(payload.signal.length, raw.length);
    expect(payload.proba.length, payload.beatCount);
    expect(payload.scores.length, payload.beatCount);
  });

  test('isolate path reports no beats for a flat signal', () async {
    final configJson = File('assets/ecg_config.json').readAsStringSync();
    final modelJson = File('assets/ecg_model_v3.json').readAsStringSync();

    final payload = await analyzeInIsolate(
      raw: List<double>.filled(360 * 20, 0.0),
      sourceFs: 360,
      configJson: configJson,
      modelJson: modelJson,
    );

    expect(payload.beatCount, 0);
    expect(payload.heartRate, isNull);
    expect(payload.scores, isEmpty);
  });
}
