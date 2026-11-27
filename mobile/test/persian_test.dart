import 'dart:math' as math;

import 'package:ecg_beat_classifier/data/analysis_worker.dart';
import 'package:ecg_beat_classifier/l10n/strings.dart';
import 'package:ecg_beat_classifier/ui/about_screen.dart';
import 'package:ecg_beat_classifier/ui/home_screen.dart';
import 'package:ecg_beat_classifier/ui/instrument_shell.dart';
import 'package:ecg_beat_classifier/ui/result_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapFa(Widget child, {Locale locale = const Locale('fa')}) =>
    MaterialApp(
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
      home: child,
    );

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

AnalysisPayload _samplePayload() {
  const fs = 360;
  final signal = List<double>.generate(fs * 12, (i) => math.sin(i / 22.0) * 0.4);
  return AnalysisPayload(
    signal: signal,
    peaks: const [180, 540, 900, 1260],
    pred: const [0, 1, 2, 0],
    proba: const [
      [0.92, 0.04, 0.04, 0.0],
      [0.10, 0.80, 0.10, 0.0],
      [0.05, 0.05, 0.90, 0.0],
      [0.90, 0.05, 0.05, 0.0],
    ],
    sampleRate: fs,
    medianRr: 360,
    heartRate: 60,
    p1: -0.4,
    p99: 0.4,
  );
}

void main() {
  setUp(() {
    appLocaleNotifier.value = const Locale('fa');
    appThemeModeNotifier.value = ThemeMode.dark;
  });

  tearDown(() {
    appLocaleNotifier.value = const Locale('en');
    appThemeModeNotifier.value = ThemeMode.dark;
  });

  testWidgets('Home screen renders in Persian correctly', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrapFa(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('طبقه‌بندی ضربان قلب ECG'), findsOneWidget);
    expect(find.text('نمونه‌های پیش‌فرض MIT-BIH'), findsOneWidget);
    expect(find.text('رکورد ۲۰۰'), findsOneWidget);
    expect(find.text('رکورد ۲۳۳'), findsOneWidget);
    expect(find.text('رکورد ۱۰۰'), findsOneWidget);
    expect(find.text('بارگذاری فایل CSV / TXT'), findsOneWidget);
    expect(find.text('تحلیل و پردازش'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('واحد سیگنال'), findsOneWidget);
    expect(find.text('معکوس کردن پلاریته'), findsOneWidget);
  });

  testWidgets('Validation error in Persian when no record selected',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrapFa(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تحلیل و پردازش'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('ابتدا یک نمونه پیش‌فرض انتخاب کنید'),
      findsOneWidget,
    );
  });

  testWidgets('About screen renders V4.0.0 metrics and limits in Persian',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrapFa(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('آزمایشگاه و اطلاعات مدل'), findsOneWidget);
    expect(find.text('V4.0.0'), findsOneWidget);
    expect(find.textContaining('پایگاه داده آریتمی MIT-BIH'), findsOneWidget);
    expect(find.text('0.972'), findsOneWidget);
    expect(find.text('0.952'), findsOneWidget);
    expect(find.text('0.179'), findsOneWidget);
    expect(find.text('0.701'), findsOneWidget);
    expect(find.text('94.7%'), findsOneWidget);
    expect(find.text('0.827'), findsOneWidget);
    expect(find.text('96.4%'), findsOneWidget);
    expect(find.textContaining('ریتم‌های دهلیزی مداوم'), findsOneWidget);
    expect(find.textContaining('نرم‌افزار پژوهشی و غیربالینی'), findsOneWidget);
  });

  testWidgets('tooltips match the active locale', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrapFa(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('تغییر زبان به انگلیسی'), findsOneWidget);
    expect(find.byTooltip('تغییر پوسته نمایش'), findsOneWidget);

    await tester.pumpWidget(_wrapFa(const HomeScreen(), locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Switch to Persian'), findsOneWidget);
    expect(find.byTooltip('Switch theme'), findsOneWidget);
  });

  testWidgets('InstrumentShell dock and ResultScreen sub-tabs work in Persian RTL',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrapFa(const InstrumentShell()));
    await tester.pumpAndSettle();

    expect(find.text('مانیتور'), findsOneWidget);
    expect(find.text('استودیو'), findsOneWidget);
    expect(find.text('آزمایشگاه'), findsOneWidget);

    await tester.pumpWidget(_wrapFa(
      ResultScreen(
        payload: _samplePayload(),
        fileName: 'fa_sample.csv',
        sourceFs: 360,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('خط زمانی'), findsOneWidget);
    await tester.tap(find.text('کالبدشکافی ضربان'));
    await tester.pumpAndSettle();
    expect(find.text('میکروسکوپ ۲۰۰ نمونه‌ای ضربان'), findsOneWidget);

    await tester.tap(find.text('ریتم R-R'));
    await tester.pumpAndSettle();
    expect(find.text('تاکوگرام ضربان‌به‌ضربان R-R'), findsOneWidget);
  });
}
