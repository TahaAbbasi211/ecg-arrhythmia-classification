import 'dart:math' as math;

import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/data/model_bundle.dart';
import 'package:ecg_beat_classifier/l10n/strings.dart';
import 'package:ecg_beat_classifier/ui/ecg_plot.dart';
import 'package:ecg_beat_classifier/ui/result_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic 5-beat result: three N, one S, one V for rich Timeline/X-Ray/Poincaré testing.
AnalysisPayload _payload() {
  const fs = 360;
  final signal = List<double>.generate(
    fs * 12,
    (i) => math.sin(i / 18.0) * 0.4,
  );
  return AnalysisPayload(
    signal: signal,
    peaks: const [180, 540, 900, 1260, 1620],
    pred: const [0, 1, 2, 0, 0],
    proba: const [
      [0.92, 0.04, 0.04, 0.0],
      [0.10, 0.80, 0.10, 0.0],
      [0.05, 0.05, 0.90, 0.0],
      [0.91, 0.05, 0.04, 0.0],
      [0.93, 0.04, 0.03, 0.0],
    ],
    scores: const [
      [0.92, 0.04, 0.04, 0.0],
      [0.10, 0.80, 0.10, 0.0],
      [0.05, 0.05, 0.90, 0.0],
      [0.91, 0.05, 0.04, 0.0],
      [0.93, 0.04, 0.03, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: -0.4,
    p99: 0.4,
  );
}

AnalysisPayload _latePayload() {
  const fs = 360;
  final signal = List<double>.generate(fs * 60, (i) => math.sin(i / 20.0) * 0.5);
  return AnalysisPayload(
    signal: signal,
    peaks: const [360, 720, 1080, 18000],
    pred: const [0, 0, 0, 2],
    proba: const [
      [0.90, 0.05, 0.05, 0.0],
      [0.90, 0.05, 0.05, 0.0],
      [0.90, 0.05, 0.05, 0.0],
      [0.05, 0.05, 0.90, 0.0],
    ],
    scores: const [
      [0.90, 0.05, 0.05, 0.0],
      [0.90, 0.05, 0.05, 0.0],
      [0.90, 0.05, 0.05, 0.0],
      [0.05, 0.05, 0.90, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: -0.5,
    p99: 0.5,
  );
}

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
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: home,
    );

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  tearDown(() {
    appLocaleNotifier.value = const Locale('en');
    appThemeModeNotifier.value = ThemeMode.dark;
  });

  testWidgets('result screen shows telemetry HUD, plot, and S/V beat timeline',
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
    expect(find.textContaining('Beats analyzed'), findsOneWidget);
    expect(find.text('60 bpm'), findsOneWidget);
    expect(find.text('S beats'), findsOneWidget);
    expect(find.text('V beats'), findsOneWidget);

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('8 s window'), findsOneWidget);
    expect(find.text('N · Normal'), findsOneWidget);
    expect(find.text('S · Supraventricular'), findsOneWidget);
    expect(find.text('V · Ventricular'), findsOneWidget);

    expect(find.text('0:01.5'), findsOneWidget);
    expect(find.text('0:02.5'), findsOneWidget);
    expect(find.text('score = 0.80'), findsOneWidget);
    expect(find.text('score = 0.90'), findsOneWidget);

    await tester.tap(find.text('0:02.5'));
    await tester.pumpAndSettle();
  });

  testWidgets('zoom chips change window size cleanly', (tester) async {
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
    await tester.tap(find.text('4s'));
    await tester.pumpAndSettle();
    expect(find.text('4 s window'), findsOneWidget);
    expect(find.text('8 s window'), findsNothing);
  });

  testWidgets('live playback toggles play/pause and advances without error',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _payload(),
        fileName: 'live.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Beat X-Ray renders 200-sample morphology, template ghost, and weighted score note',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _payload(),
        fileName: 'xray.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beat X-Ray'));
    await tester.pumpAndSettle();

    expect(find.text('200-Sample Morphology X-Ray'), findsOneWidget);
    expect(find.text('Median template (ghost)'), findsOneWidget);
    expect(find.text('score = 0.80'), findsOneWidget);
    expect(find.textContaining('relative, uncalibrated ranking score'), findsOneWidget);
  });

  testWidgets('R-R Rhythm tab renders Tachogram and Poincare plot without exceptions',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(
      ResultScreen(
        payload: _payload(),
        fileName: 'rhythm.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('R-R Rhythm'));
    await tester.pumpAndSettle();

    expect(find.text('Beat-to-Beat R-R Tachogram'), findsOneWidget);
    expect(find.textContaining('Poincaré HRV Plot'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('the screen title follows the current language', (tester) async {
    _tall(tester);
    final sample = sampleRecords.firstWhere((record) => record.id == '200');

    await tester.pumpWidget(_app(
      ResultScreen(payload: _payload(), sample: sample, sourceFs: 360),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Record 200'), findsOneWidget);

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

  testWidgets('all studio views fit a 320 px phone in both languages',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final locale in const [Locale('en'), Locale('fa')]) {
      final s = locale.languageCode == 'fa';
      await tester.pumpWidget(_app(
        ResultScreen(
          payload: _payload(),
          fileName: 'record_200.csv',
          sourceFs: 360,
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${locale.languageCode} timeline');

      await tester.tap(find.text(s ? 'کالبدشکافی ضربان' : 'Beat X-Ray'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${locale.languageCode} xray');

      await tester.tap(find.text(s ? 'ریتم R-R' : 'R-R Rhythm'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${locale.languageCode} rhythm');
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

    expect(find.text('score = 0.57'), findsOneWidget);
  });
}
