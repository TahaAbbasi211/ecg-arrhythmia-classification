import 'package:ecg_beat_classifier/data/signal_parser.dart';
import 'package:ecg_beat_classifier/ui/about_screen.dart';
import 'package:ecg_beat_classifier/ui/home_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: child,
    );

void main() {
  test('parser takes the first numeric column and ignores headers', () {
    final parsed = parseSignalText('MLII_mV\n0.86\n0.765\n\n# comment\n0.645\n');
    expect(parsed.values, [0.86, 0.765, 0.645]);
    expect(parsed.skippedLines, 3);
  });

  test('parser handles comma separated rows', () {
    // The first numeric column wins, so "t,value" rows yield the time column.
    final parsed = parseSignalText('t,value\n0,1.5\n1,2.5\n');
    expect(parsed.values, [0.0, 1.0]);
  });

  test('parser skips a non-numeric first column', () {
    final parsed = parseSignalText('time,MLII\n0.0,1.5\n0.1,2.5\n');
    expect(parsed.values, [0.0, 0.1]);
  });

  testWidgets('home screen renders the samples, rate field and analyze button',
      (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('ECG Beat Classifier'), findsOneWidget);
    expect(find.text('Record 200'), findsOneWidget);
    expect(find.text('Record 100'), findsOneWidget);
    expect(find.text('Record 233'), findsOneWidget);
    expect(find.text('Import CSV'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '360'), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
  });

  testWidgets('analyze without a selection shows a friendly message',
      (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pick a demo record'), findsOneWidget);
  });

  testWidgets('sampling rate outside 100-2000 is rejected', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '50');
    await tester.ensureVisible(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();

    expect(find.textContaining('between 100 and 2000'), findsOneWidget);
  });

  testWidgets('about screen states the results and the disclaimer',
      (tester) async {
    // A tall viewport so the whole page is laid out and findable.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('MIT-BIH Arrhythmia Database'), findsOneWidget);
    expect(find.textContaining('22 patients for training'), findsOneWidget);
    expect(find.textContaining('22 different patients for testing'),
        findsOneWidget);
    expect(find.text('0.965'), findsOneWidget);
    expect(find.text('0.926'), findsOneWidget);
    expect(find.text('0.180'), findsOneWidget);
    expect(find.text('0.69'), findsOneWidget);
    expect(find.textContaining('S beats are weak'), findsOneWidget);
    expect(find.textContaining('Fusion (F) beats are not predicted'),
        findsOneWidget);
    expect(find.textContaining('Single lead only'), findsOneWidget);
    expect(find.text('Educational project, not a medical device.'),
        findsOneWidget);
  });
}
