/// Pure UI telemetry view-model computed from [AnalysisPayload] without altering `lib/ecg/`.
library;

import 'dart:math' as math;

import '../data/analysis_worker.dart';
import '../data/model_bundle.dart';
import '../ecg/constants.dart' as ecg_constants;
import '../l10n/strings.dart';
import 'theme.dart';

enum TimelineFilter { abnormal, all, sOnly, vOnly, nOnly }

class EcgBeatEntry {
  const EcgBeatEntry({
    required this.index,
    required this.peakSample,
    required this.timeSeconds,
    required this.classIndex,
    required this.proba,
    required this.scores,
    required this.prevRrMs,
    required this.nextRrMs,
    required this.rrRatio,
  });

  final int index;
  final int peakSample;
  final double timeSeconds;
  final int classIndex;
  final List<double> proba;
  final List<double> scores;
  final double? prevRrMs;
  final double? nextRrMs;
  final double? rrRatio;

  bool get isAbnormal => classIndex == 1 || classIndex == 2;
  double get activeScore =>
      classIndex >= 0 && classIndex < scores.length ? scores[classIndex] : 0.0;
}

class TachogramPoint {
  const TachogramPoint({
    required this.beatIndex,
    required this.timeSeconds,
    required this.rrMs,
    required this.classIndex,
  });

  final int beatIndex;
  final double timeSeconds;
  final double rrMs;
  final int classIndex;
}

class PoincarePoint {
  const PoincarePoint({
    required this.beatIndex,
    required this.rrPrevMs,
    required this.rrNextMs,
    required this.classIndex,
  });

  final int beatIndex;
  final double rrPrevMs;
  final double rrNextMs;
  final int classIndex;
}

class AnalysisSessionEntry {
  AnalysisSessionEntry({
    required this.id,
    required this.payload,
    required this.sourceFs,
    this.sample,
    this.fileName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final AnalysisPayload payload;
  final double sourceFs;
  final SampleRecord? sample;
  final String? fileName;
  final DateTime timestamp;

  String resolveTitle(AppStrings s) {
    final rec = sample;
    if (rec != null) return s.sampleTitle(rec.id, rec.title);
    return fileName ?? s.importedCsvTitle;
  }
}

class EcgViewModel {
  EcgViewModel._({
    required this.payload,
    required this.sourceFs,
    required this.durationSeconds,
    required this.beats,
    required this.abnormalBeats,
    required this.medianRrMs,
    required this.minRrMs,
    required this.maxRrMs,
    required this.bpm,
    required this.normalCount,
    required this.sCount,
    required this.vCount,
    required this.normalPct,
    required this.ectopicBurdenPct,
    required this.medianTemplate,
    required this.tachogramPoints,
    required this.poincarePoints,
  });

  final AnalysisPayload payload;
  final double sourceFs;
  final double durationSeconds;
  final List<EcgBeatEntry> beats;
  final List<EcgBeatEntry> abnormalBeats;
  final double? medianRrMs;
  final double? minRrMs;
  final double? maxRrMs;
  final int? bpm;
  final int normalCount;
  final int sCount;
  final int vCount;
  final double normalPct;
  final double ectopicBurdenPct;
  final List<double>? medianTemplate;
  final List<TachogramPoint> tachogramPoints;
  final List<PoincarePoint> poincarePoints;

  int get beatCount => beats.length;
  double get totalSamples => payload.signal.length.toDouble();

  /// Round to tenths first so 59.99 s renders `1:00.0`, never `0:60.0`.
  static String formatTimestamp(double timeSeconds) {
    final totalTenths = math.max(0, (timeSeconds * 10).round());
    final minutes = totalTenths ~/ 600;
    final seconds = (totalTenths % 600) / 10.0;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }

  /// Format duration as `m:ss`.
  static String formatDurationMmSs(double timeSeconds) {
    final totalSecs = math.max(0, timeSeconds.round());
    final minutes = totalSecs ~/ 60;
    final seconds = totalSecs % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static double _medianList(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return 0.5 * (sorted[mid - 1] + sorted[mid]);
  }

  /// Compute baseline-centered 200-sample beat window `[peak - 90 .. peak + 110)`.
  List<double>? extractBeatWindow(int beatIndex) {
    if (beatIndex < 0 || beatIndex >= beats.length) return null;
    final peak = beats[beatIndex].peakSample;
    return _centeredWindow(payload.signal, peak);
  }

  static List<double>? _centeredWindow(List<double> signal, int peak) {
    final start = peak - ecg_constants.pre;
    final end = peak + ecg_constants.post;
    if (start < 0 || end > signal.length) return null;
    final win = signal.sublist(start, end);
    final base = _medianList(win);
    return <double>[for (final v in win) v - base];
  }

  static List<double>? _computeMedianTemplate(
    List<double> signal,
    List<int> orderByTime,
    List<int> peaks,
    List<int> pred,
  ) {
    final normalWindows = <List<double>>[];
    final allWindows = <List<double>>[];
    for (final idx in orderByTime) {
      final w = _centeredWindow(signal, peaks[idx]);
      if (w == null || w.length != ecg_constants.beatLength) continue;
      allWindows.add(w);
      if (pred[idx] == 0) normalWindows.add(w);
    }
    final source = normalWindows.length >= 3 ? normalWindows : allWindows;
    if (source.isEmpty) return null;

    final n = ecg_constants.beatLength;
    final col = List<double>.filled(source.length, 0.0);
    final template = List<double>.filled(n, 0.0);
    for (var s = 0; s < n; s++) {
      for (var b = 0; b < source.length; b++) {
        col[b] = source[b][s];
      }
      template[s] = _medianList(col);
    }
    return template;
  }

  factory EcgViewModel.fromPayload(
    AnalysisPayload payload, {
    double sourceFs = 360.0,
  }) {
    final fs = payload.sampleRate > 0 ? payload.sampleRate.toDouble() : 360.0;
    final duration = fs > 0 ? payload.signal.length / fs : 0.0;
    final count = math.min(
      payload.peaks.length,
      math.min(payload.pred.length, payload.proba.length),
    );

    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) => payload.peaks[a].compareTo(payload.peaks[b]));

    final rrSamples = <double>[
      for (var i = 1; i < order.length; i++)
        (payload.peaks[order[i]] - payload.peaks[order[i - 1]]).toDouble(),
    ];
    final medRrSamples = payload.medianRr ??
        (rrSamples.isNotEmpty ? _medianList(rrSamples) : null);
    final medRrMs = (medRrSamples != null && medRrSamples > 0)
        ? medRrSamples * 1000.0 / fs
        : null;

    final beats = <EcgBeatEntry>[];
    final tachogram = <TachogramPoint>[];
    final poincare = <PoincarePoint>[];
    double? minRrMs;
    double? maxRrMs;

    for (var rank = 0; rank < order.length; rank++) {
      final orig = order[rank];
      final peak = payload.peaks[orig];
      final cls = payload.pred[orig];
      final prevMs = rank > 0
          ? (peak - payload.peaks[order[rank - 1]]) * 1000.0 / fs
          : null;
      final nextMs = rank + 1 < order.length
          ? (payload.peaks[order[rank + 1]] - peak) * 1000.0 / fs
          : null;
      final ratio = (prevMs != null && medRrMs != null && medRrMs > 0)
          ? prevMs / medRrMs
          : null;

      final sc = orig < payload.scores.length
          ? payload.scores[orig]
          : const <double>[1.0, 0.0, 0.0, 0.0];

      beats.add(
        EcgBeatEntry(
          index: rank,
          peakSample: peak,
          timeSeconds: peak / fs,
          classIndex: cls,
          proba: payload.proba[orig],
          scores: sc,
          prevRrMs: prevMs,
          nextRrMs: nextMs,
          rrRatio: ratio,
        ),
      );

      if (prevMs != null && prevMs > 0) {
        minRrMs = minRrMs == null ? prevMs : math.min(minRrMs, prevMs);
        maxRrMs = maxRrMs == null ? prevMs : math.max(maxRrMs, prevMs);
        tachogram.add(
          TachogramPoint(
            beatIndex: rank,
            timeSeconds: peak / fs,
            rrMs: prevMs,
            classIndex: cls,
          ),
        );
      }
      if (prevMs != null && prevMs > 0 && nextMs != null && nextMs > 0) {
        poincare.add(
          PoincarePoint(
            beatIndex: rank,
            rrPrevMs: prevMs,
            rrNextMs: nextMs,
            classIndex: cls,
          ),
        );
      }
    }

    final nCnt = payload.countOf(0);
    final sCnt = payload.countOf(1);
    final vCnt = payload.countOf(2);
    final total = math.max(1, beats.length);
    final abnormal = <EcgBeatEntry>[
      for (final b in beats)
        if (b.isAbnormal) b,
    ];

    final template = _computeMedianTemplate(
      payload.signal,
      order,
      payload.peaks,
      payload.pred,
    );

    final computedBpm = payload.heartRate?.round() ??
        ((medRrMs != null && medRrMs > 0) ? (60000.0 / medRrMs).round() : null);

    return EcgViewModel._(
      payload: payload,
      sourceFs: sourceFs,
      durationSeconds: duration,
      beats: beats,
      abnormalBeats: abnormal,
      medianRrMs: medRrMs,
      minRrMs: minRrMs,
      maxRrMs: maxRrMs,
      bpm: computedBpm,
      normalCount: nCnt,
      sCount: sCnt,
      vCount: vCnt,
      normalPct: (nCnt / total) * 100.0,
      ectopicBurdenPct: ((sCnt + vCnt) / total) * 100.0,
      medianTemplate: template,
      tachogramPoints: tachogram,
      poincarePoints: poincare,
    );
  }

  List<EcgBeatEntry> filteredBeats(TimelineFilter filter) {
    switch (filter) {
      case TimelineFilter.abnormal:
        return abnormalBeats;
      case TimelineFilter.all:
        return beats;
      case TimelineFilter.sOnly:
        return <EcgBeatEntry>[
          for (final b in beats)
            if (b.classIndex == 1) b,
        ];
      case TimelineFilter.vOnly:
        return <EcgBeatEntry>[
          for (final b in beats)
            if (b.classIndex == 2) b,
        ];
      case TimelineFilter.nOnly:
        return <EcgBeatEntry>[
          for (final b in beats)
            if (b.classIndex == 0) b,
        ];
    }
  }

  int? nearestBeatIndex(double targetSample, {double? maxDistanceSamples}) {
    if (beats.isEmpty) return null;
    var bestIdx = 0;
    var bestDist = (beats[0].peakSample - targetSample).abs();
    for (var i = 1; i < beats.length; i++) {
      final d = (beats[i].peakSample - targetSample).abs();
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (maxDistanceSamples != null && bestDist > maxDistanceSamples) {
      return null;
    }
    return bestIdx;
  }

  String buildClipboardSummary(AppStrings s, {required String title}) {
    final buf = StringBuffer()
      ..writeln('${s.brandName} ${s.appVersion} — $title')
      ..writeln('${s.durationLabel}: ${formatDurationMmSs(durationSeconds)} · '
          '${s.beatsAnalyzed}: $beatCount · '
          '${s.heartRate}: ${s.bpmValue(bpm)}')
      ..writeln(
        'N: $normalCount (${normalPct.toStringAsFixed(1)}%) · '
        'S: $sCount · V: $vCount · '
        '${s.ectopicBurdenLabel}: ${ectopicBurdenPct.toStringAsFixed(1)}%',
      );
    if (medianRrMs != null) {
      buf.writeln('${s.medianRrLabel}: ${medianRrMs!.round()} ms');
    }
    if (abnormalBeats.isEmpty) {
      buf.writeln('${s.sAndVBeats}: 0 (${s.noArrhythmiaDetected})');
    } else {
      buf.writeln('${s.sAndVBeats} (${abnormalBeats.length}):');
      for (final b in abnormalBeats.take(15)) {
        buf.writeln(
          '  - ${formatTimestamp(b.timeSeconds)} · '
          '${classLabels[b.classIndex]} '
          '(score = ${b.activeScore.toStringAsFixed(2)})',
        );
      }
      if (abnormalBeats.length > 15) {
        buf.writeln('  ... +${abnormalBeats.length - 15} more');
      }
    }
    buf
      ..writeln()
      ..writeln(s.disclaimer);
    return buf.toString().trimRight();
  }
}
