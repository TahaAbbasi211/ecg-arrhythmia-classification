import 'dart:math' as math;

import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/data/model_bundle.dart';
import 'package:ecg_beat_classifier/ui/ecg_plot.dart';
import 'package:ecg_beat_classifier/ui/result_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small synthetic result: 3 analyzed beats, one N, one S, one V.
AnalysisPayload _payload() {
  const fs = 360;
  final signal = List<double>.generate(fs * 12, (i) => (i % 40) / 100.0);
  return AnalysisPayload(
    signal: signal,
    peaks: const [180, 540, 900],
    pred: const [0, 1, 2],
    proba: const [
      [0.9, 0.05, 0.05, 0.0],
      [0.1, 0.8, 0.1, 0.0],
      [0.05, 0.05, 0.9, 0.0],
    ],
    scores: const [
      [0.9, 0.05, 0.05, 0.0],
      [0.1, 0.8, 0.1, 0.0],
      [0.05, 0.05, 0.9, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: 0.0,
    p99: 0.4,
  );
}

/// 60 s with one late V beat, so the plot has somewhere to scroll.
AnalysisPayload _latePayload() {
  const fs = 360;
  final signal = List<double>.generate(fs * 60, (i) => math.sin(i / 20.0) * 0.5);
  return AnalysisPayload(
    signal: signal,
    peaks: const [18000],
    pred: const [2],
    proba: const [
      [0.05, 0.05, 0.9, 0.0],
    ],
    scores: const [
      [0.05, 0.05, 0.9, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: -0.5,
    p99: 0.5,
  );
}

/// One beat 20 ms before a full minute: rounding to tenths must not print 0:60.0.
AnalysisPayload _edgePayload() {
  const fs = 360;
  final signal = List<double>.generate(fs * 61, (i) => math.sin(i / 20.0) * 0.5);
  return AnalysisPayload(
    signal: signal,
    peaks: const [21593],
    pred: const [2],
    proba: const [
      [0.05, 0.05, 0.9, 0.0],
    ],
    scores: const [
      [0.05, 0.05, 0.9, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: -0.5,
    p99: 0.5,
  );
}

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      home: home,
    );

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('result screen shows the summary, plot and S/V beat list',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _payload(),
        fileName: 'record_200.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('record_200.csv'), findsOneWidget);

    // Four summary cards.
    expect(find.text('Beats analyzed'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('60 bpm'), findsOneWidget);
    expect(find.text('S beats'), findsOneWidget);
    expect(find.text('V beats'), findsOneWidget);

    // Plot, window slider and legend.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('8 s window'), findsOneWidget);
    expect(find.text('N · Normal'), findsOneWidget);
    expect(find.text('S · Supraventricular'), findsOneWidget);
    expect(find.text('V · Ventricular'), findsOneWidget);

    // The S and V beats are listed with time and normalized score.
    expect(find.text('S and V beats'), findsOneWidget);
    expect(find.text('0:01.5'), findsOneWidget);
    expect(find.text('0:02.5'), findsOneWidget);
    expect(find.text('score = 0.80'), findsOneWidget);
    expect(find.text('score = 0.90'), findsOneWidget);

    // Tapping a row moves the plot without throwing.
    await tester.tap(find.text('0:02.5'));
    await tester.pumpAndSettle();
  });

  testWidgets('window slider changes the visible window', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _payload(),
        fileName: 'record_200.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('8 s window'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('8 s window'), findsNothing);
  });

  testWidgets('a beat just under a minute reads 1:00.0, never 0:60.0',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _edgePayload(),
        fileName: 'edge.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1:00.0'), findsOneWidget);
    expect(find.text('0:60.0'), findsNothing);
  });

  testWidgets('the app bar title follows the current language', (tester) async {
    _tall(tester);
    final sample = sampleRecords.firstWhere((record) => record.id == '200');

    await tester.pumpWidget(_app(
      ResultScreen(payload: _payload(), sample: sample, sourceFs: 360),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Record 200'), findsOneWidget);

    // Same widget, same state: only the language changed.
    await tester.pumpWidget(_app(
      ResultScreen(payload: _payload(), sample: sample, sourceFs: 360),
      locale: const Locale('fa'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('رکورد ۲۰۰'), findsOneWidget);
    expect(find.text('Record 200'), findsNothing);
  });

  testWidgets('the S and V list is in time order even when classes interleave',
      (tester) async {
    _tall(tester);
    const fs = 360;
    final payload = AnalysisPayload(
      signal: List<double>.generate(fs * 12, (i) => (i % 40) / 100.0),
      peaks: const [180, 540, 900],
      // V comes first in the prediction array, S later.
      pred: const [2, 0, 1],
      proba: const [
        [0.05, 0.05, 0.9, 0.0],
        [0.9, 0.05, 0.05, 0.0],
        [0.1, 0.8, 0.1, 0.0],
      ],
      sampleRate: fs,
      medianRr: 360,
      heartRate: 60,
      p1: 0.0,
      p99: 0.4,
    );

    await tester.pumpWidget(_app(
      ResultScreen(payload: payload, fileName: 'mixed.csv', sourceFs: 360),
    ));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('0:00.5')).dy;
    final second = tester.getTopLeft(find.text('0:02.5')).dy;
    expect(first, lessThan(second));
  });

  testWidgets('summary cards fit a 320 px phone in both languages',
      (tester) async {
    // The narrowest phone we support: four cards cannot be side by side, and a
    // RenderFlex overflow would surface as an exception here.
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final locale in const [Locale('en'), Locale('fa')]) {
      await tester.pumpWidget(_app(
        ResultScreen(payload: _latePayload(), fileName: 'record_200.csv', sourceFs: 360),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: locale.languageCode);
    }
  });

  testWidgets('tapping a late beat scrolls the plot to it', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _latePayload(),
        fileName: 'late.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    final plot = tester.widget<EcgPlot>(find.byType(EcgPlot));
    expect(plot.scrollController.offset, 0);

    await tester.tap(find.text('0:50.0'));
    await tester.pumpAndSettle();
    expect(plot.scrollController.offset, greaterThan(1000));
  });

  testWidgets('result screen computes normalized weighted scores by default',
      (tester) async {
    _tall(tester);
    const fs = 360;
    final payload = AnalysisPayload(
      signal: List<double>.generate(fs * 12, (i) => (i % 40) / 100.0),
      peaks: const [540],
      pred: const [1],
      proba: const [
        [0.1, 0.8, 0.1, 0.0],
      ],
      sampleRate: fs,
      medianRr: 360,
      heartRate: 60,
      p1: 0.0,
      p99: 0.4,
    );

    await tester.pumpWidget(_app(
      ResultScreen(payload: payload, fileName: 'weighted.csv', sourceFs: 360),
    ));
    await tester.pumpAndSettle();

    // [0.1*1, 0.8*0.25, 0.1*0.5, 0] = [0.1, 0.2, 0.05, 0] / 0.35 -> 0.5714
    expect(find.text('score = 0.57'), findsOneWidget);
  });
}