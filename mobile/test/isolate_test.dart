import 'dart:convert';
import 'dart:io';

import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/data/signal_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end check of the isolate path the app actually uses.
void main() {
  test('analysis runs in an isolate and matches the reference counts', () async {
    final configJson =
        jsonDecode(File('assets/ecg_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final forestJson =
        jsonDecode(File('assets/ecg_forest.json').readAsStringSync())
            as Map<String, dynamic>;
    final raw = parseSignalText(
      File('assets/samples/record_200.csv').readAsStringSync(),
    ).values;

    final payload = await analyzeInIsolate(
      raw: raw,
      sourceFs: 360,
      configJson: configJson,
      forestJson: forestJson,
    );

    // Reference values for the bundled 60 s record 200 CSV, produced by
    // `portable.analyze_reference` in the Python project.
    expect(payload.beatCount, 81);
    expect(payload.countOf(0), 37);
    expect(payload.countOf(1), 0);
    expect(payload.countOf(2), 44);
    expect(payload.heartRate, isNotNull);
    expect(payload.heartRate!, closeTo(89.26, 0.05));
    expect(payload.signal.length, raw.length);
    expect(payload.proba.length, payload.beatCount);
  });

  test('isolate path reports no beats for a flat signal', () async {
    final configJson =
        jsonDecode(File('assets/ecg_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final forestJson =
        jsonDecode(File('assets/ecg_forest.json').readAsStringSync())
            as Map<String, dynamic>;

    final payload = await analyzeInIsolate(
      raw: List<double>.filled(360 * 20, 0.0),
      sourceFs: 360,
      configJson: configJson,
      forestJson: forestJson,
    );

    expect(payload.beatCount, 0);
    expect(payload.heartRate, isNull);
  });
}
