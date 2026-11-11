import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/ui/result_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small synthetic result: 3 analyzed beats, one N, one S, one V.
AnalysisPayload _payload() {
  const fs = 360;
  final signal = List<double>.generate(fs * 4, (i) => (i % 40) / 100.0);
  return AnalysisPayload(
    signal: signal,
    peaks: const [180, 540, 900],
    pred: const [0, 1, 2],
    proba: const [
      [0.9, 0.05, 0.05, 0.0],
      [0.1, 0.8, 0.1, 0.0],
      [0.05, 0.05, 0.9, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
  );
}

void main() {
  testWidgets('result screen shows the summary, plot and S/V beat list',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: ResultScreen(payload: _payload(), title: 'Record 200', sourceFs: 360),
    ));
    await tester.pumpAndSettle();

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

    // The S and V beats are listed with time and probability.
    expect(find.text('S and V beats'), findsOneWidget);
    expect(find.text('0:01.5'), findsOneWidget);
    expect(find.text('0:02.5'), findsOneWidget);
    expect(find.text('p = 0.80'), findsOneWidget);
    expect(find.text('p = 0.90'), findsOneWidget);

    // Tapping a row moves the plot without throwing.
    await tester.tap(find.text('0:02.5'));
    await tester.pumpAndSettle();
  });

  testWidgets('window slider changes the visible window', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: ResultScreen(payload: _payload(), title: 'Record 200', sourceFs: 360),
    ));
    await tester.pumpAndSettle();

    expect(find.text('8 s window'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('8 s window'), findsNothing);
  });
}
