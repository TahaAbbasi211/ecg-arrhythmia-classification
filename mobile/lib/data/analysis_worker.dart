/// Runs the analysis in a background isolate so the UI never freezes.
library;

import 'dart:convert';
import 'dart:isolate';

import '../ecg/analyze.dart';
import '../ecg/forest.dart';

/// A flat, isolate-friendly result: plain lists only.
class AnalysisPayload {
  AnalysisPayload({
    required this.signal,
    required this.peaks,
    required this.pred,
    required this.proba,
    required this.sampleRate,
    required this.medianRr,
    required this.heartRate,
    this.p1 = 0.0,
    this.p99 = 0.0,
  });

  final List<double> signal;
  final List<int> peaks;
  final List<int> pred;
  final List<List<double>> proba;
  final int sampleRate;
  final double? medianRr;
  final double? heartRate;

  /// 1st and 99th percentile of the filtered signal. The plot scales its
  /// vertical axis to these, so one spike cannot squash the whole trace.
  final double p1;
  final double p99;

  int get beatCount => pred.length;

  int countOf(int classIndex) => pred.where((p) => p == classIndex).length;
}

class _Request {
  _Request(this.raw, this.sourceFs, this.configJson, this.forestJson);

  final List<double> raw;
  final double sourceFs;
  final String configJson;
  final String forestJson;
}

AnalysisPayload _run(_Request req) {
  // jsonDecode and the tree building happen here, off the UI thread.
  final config = EcgConfig.fromJson(
    jsonDecode(req.configJson) as Map<String, dynamic>,
  );
  final forest = Forest.fromJson(
    jsonDecode(req.forestJson) as Map<String, dynamic>,
  );
  final result = EcgAnalyzer(config: config, forest: forest)
      .analyze(req.raw, req.sourceFs);
  return AnalysisPayload(
    signal: result.signal,
    peaks: result.peaks,
    pred: result.pred,
    proba: result.proba,
    sampleRate: result.sampleRate,
    medianRr: result.medianRr,
    heartRate: result.heartRate,
    p1: result.p1,
    p99: result.p99,
  );
}

/// Analyze [raw] off the UI thread.
///
/// The bundled JSON is handed over as text: decoding it on the UI thread would
/// stall the first frame for a second or more.
Future<AnalysisPayload> analyzeInIsolate({
  required List<double> raw,
  required double sourceFs,
  required String configJson,
  required String forestJson,
}) {
  return Isolate.run(
    () => _run(_Request(raw, sourceFs, configJson, forestJson)),
  );
}