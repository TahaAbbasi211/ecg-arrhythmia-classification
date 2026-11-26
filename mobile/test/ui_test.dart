import 'dart:math' as math;

import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/data/signal_parser.dart';
import 'package:ecg_beat_classifier/ui/about_screen.dart';
import 'package:ecg_beat_classifier/ui/ecg_plot.dart';
import 'package:ecg_beat_classifier/ui/home_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      home: child,
    );

/// A tall phone, so the whole home form is laid out and findable.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 60 s at 360 Hz: the case where samples outnumber pixels about 7 to 1.
AnalysisPayload _longPayload() {
  const fs = 360;
  final signal = List<double>.generate(
    fs * 60,
    (i) => math.sin(i / 25.0) * 0.4,
  );
  return AnalysisPayload(
    signal: signal,
    peaks: const [180, 5400, 21400],
    pred: const [0, 1, 2],
    proba: const [
      [0.9, 0.05, 0.05, 0.0],
      [0.1, 0.8, 0.1, 0.0],
      [0.05, 0.05, 0.9, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: -0.4,
    p99: 0.4,
  );
}

EcgTracePainter _painter(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<EcgTracePainter>();
  return painters.single;
}

void main() {
  test('parser takes the only numeric column and skips comments', () {
    final parsed = parseSignalText(
      'MLII_mV\n0.86\n0.765\n\n# comment\n// another\n0.645\n',
    );
    expect(parsed.values, [0.86, 0.765, 0.645]);
    expect(parsed.skippedLines, 3);
  });

  test('parser drops a leading time column instead of plotting it', () {
    // Time rises evenly, so the second column is the ECG.
    final parsed = parseSignalText('t,value\n0,1.5\n1,2.5\n');
    expect(parsed.values, [1.5, 2.5]);
    expect(parsed.timeColumn, 't');
  });

  test('parser treats a column named t as time, but not voltage', () {
    const csv = 't,ecg\n0,1\n0.03,2\n0.08,3\n';
    final parsed = parseSignalText(csv);
    expect(parsed.timeColumn, 't');
    expect(parsed.values, <double>[1, 2, 3]);

    // Substring matching would make 'voltage' a time axis and drop the ECG.
    const wrong = 'voltage,value\n0.9,1\n0.1,2\n0.05,3\n';
    expect(parseSignalText(wrong).values, <double>[0.9, 0.1, 0.05]);
  });

  test('parser recognizes a time header over a monotonic column', () {
    final parsed = parseSignalText('time,MLII\n0.0,1.5\n0.1,2.5\n');
    expect(parsed.values, [1.5, 2.5]);
  });

  test('parser keeps the time column when it is the only signal column', () {
    // Two uneven steps are not a clock, so this is a signal after all.
    final parsed = parseSignalText('x\n0.0\n1.0\n7.0\n');
    expect(parsed.values, [0.0, 1.0, 7.0]);
  });

  test('parser drops both sample and time columns in a three-column CSV', () {
    const csv =
        'sample,time_s,MLII_mV\n0,0.000,0.12\n1,0.003,0.45\n2,0.006,-0.20\n';
    final parsed = parseSignalText(csv);
    expect(parsed.columnName, 'MLII_mV');
    expect(parsed.values, [0.12, 0.45, -0.20]);
  });

  test('Persian and Arabic digits parse as a sampling rate', () {
    expect(parseSamplingRate('۳۶۰'), 360);
    expect(parseSamplingRate('٣٦٠'), 360);
    // The Arabic decimal separator, and a stray thousands separator.
    expect(parseSamplingRate('360٫0'), 360);
    expect(parseSamplingRate('1٬000'), 1000);
    expect(parseSamplingRate(''), isNull);
  });

  testWidgets('home screen renders the samples, rate field and analyze button',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('ECG Beat Classifier'), findsOneWidget);
    expect(find.text('Record 200'), findsOneWidget);
    expect(find.text('Record 100'), findsOneWidget);
    expect(find.text('Record 233'), findsOneWidget);
    expect(find.text('Import CSV'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '360'), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
    // Unit and polarity controls are always visible, so a wrong-unit file can
    // be fixed before the first analysis instead of after a bad one.
    expect(find.text('Signal unit'), findsOneWidget);
    expect(find.text('Invert polarity'), findsOneWidget);
  });

  testWidgets('selecting a demo record resets the rate to 360', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '500');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '500'), findsOneWidget);

    await tester.tap(find.text('Record 200'));
    await tester.pumpAndSettle();

    // The bundled records are 360 Hz; a leftover 500 would mislabel every beat.
    expect(find.widgetWithText(TextFormField, '360'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '500'), findsNothing);
  });

  testWidgets('analyze without a selection shows a friendly message',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pick a demo record'), findsOneWidget);
  });

  testWidgets('sampling rate outside 100-2000 is rejected', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '50');
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();

    expect(find.textContaining('between 100 and 2000'), findsOneWidget);
  });

  testWidgets('a second tap while analyzing does not start a second analysis',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record 200'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Analyze'));
    await tester.pump();
    expect(find.text('Analyzing…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Analyzing…'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('60 s plot scales by the content width, not the viewport',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(
      Center(
        child: SizedBox(
          width: 400,
          height: 180,
          child: EcgPlot(
            payload: _longPayload(),
            windowSeconds: 8,
            scrollController: controller,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final painter = _painter(tester);
    // 60 s at 360 Hz over an 8 s / 400 px window is 3000 px of content.
    expect(painter.contentWidth(400), closeTo(3000, 0.5));
    expect(painter.pxPerSampleFor(400), closeTo(3000 / 21600, 1e-9));
    expect(painter.pxPerSampleFor(400), lessThan(1.0));
    // The old code stretched the trace 7.5x past the end of the content.
    expect(painter.xForSample(21600, 400), closeTo(3000, 0.5));
    expect(painter.xForSample(2880, 400), closeTo(400, 0.5));
    expect(controller.position.maxScrollExtent, closeTo(2600, 0.5));
  });

  testWidgets('a Persian locale still scrolls the plot left to right',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(
      Center(
        child: SizedBox(
          width: 400,
          height: 180,
          child: EcgPlot(
            payload: _longPayload(),
            windowSeconds: 8,
            scrollController: controller,
          ),
        ),
      ),
      locale: const Locale('fa'),
    ));
    await tester.pumpAndSettle();

    // Without this the RTL ambient directionality reverses the scroll view.
    expect(
      find.descendant(
        of: find.byType(EcgPlot),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.ltr,
        ),
      ),
      findsOneWidget,
    );

    await tester.drag(find.byType(EcgPlot), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  test('min-max envelope keeps a one-pixel spike', () {
    final signal = List<double>.filled(21600, 0.0);
    signal[5000] = 5.0;
    final envelope = EcgTracePainter.envelope(
      signal,
      pxPerSample: 3000 / 21600,
      offset: 0,
      columns: 3000,
    );
    final bands = envelope.whereType<ColumnEnvelope>().toList();
    expect(bands.length, 3000);
    expect(bands.map((band) => band.max).reduce(math.max), 5.0);
    expect(bands.map((band) => band.min).reduce(math.min), 0.0);
  });

  test('min-max envelope follows the scroll offset', () {
    final signal = List<double>.generate(21600, (i) => i.toDouble());
    final envelope = EcgTracePainter.envelope(
      signal,
      pxPerSample: 0.2,
      offset: 400,
      columns: 100,
    );
    final first = envelope[0]!;
    // Column 0 starts at sample 2000, not at sample 0.
    expect(first.min, closeTo(2000, 1));
    expect(first.max, closeTo(2004, 1));
  });

  testWidgets('about screen states the results and the disclaimer',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('V2.1.0'), findsOneWidget);
    expect(find.textContaining('MIT-BIH Arrhythmia Database'), findsOneWidget);
    expect(find.textContaining('22 patients for training'), findsOneWidget);
    expect(find.textContaining('22 different patients for testing'),
        findsOneWidget);
    expect(find.text('0.965'), findsOneWidget);
    expect(find.text('0.923'), findsOneWidget);
    expect(find.text('0.177'), findsOneWidget);
    expect(find.text('0.688'), findsOneWidget);
    expect(find.textContaining('S beats are weak'), findsOneWidget);
    expect(find.textContaining('Fusion (F) beats are not predicted'),
        findsOneWidget);
    expect(find.textContaining('Single lead only'), findsOneWidget);
    expect(
      find.text(
        'Research and non-clinical software — not a certified medical device '
        'and not intended for clinical diagnosis or treatment decisions.',
      ),
      findsOneWidget,
    );
  });
}