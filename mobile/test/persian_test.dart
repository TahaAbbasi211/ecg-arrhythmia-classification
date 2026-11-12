import 'package:ecg_beat_classifier/l10n/strings.dart';
import 'package:ecg_beat_classifier/ui/about_screen.dart';
import 'package:ecg_beat_classifier/ui/home_screen.dart';
import 'package:ecg_beat_classifier/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapFa(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      home: child,
    );

void main() {
  testWidgets('Home screen renders in Persian correctly', (tester) async {
    appLocaleNotifier.value = const Locale('fa');
    await tester.pumpWidget(_wrapFa(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('طبقه‌بندی ضربان قلب ECG'), findsOneWidget);
    expect(find.text('نمونه‌های پیش‌فرض'), findsOneWidget);
    expect(find.text('رکورد ۲۰۰'), findsOneWidget);
    expect(find.text('رکورد ۱۰۰'), findsOneWidget);
    expect(find.text('رکورد ۲۳۳'), findsOneWidget);
    expect(find.text('بارگذاری فایل CSV'), findsOneWidget);
    expect(find.text('تحلیل و پردازش'), findsOneWidget);
    expect(find.text('English'), findsOneWidget); // Language switch button
  });

  testWidgets('Validation error in Persian when no record selected', (tester) async {
    appLocaleNotifier.value = const Locale('fa');
    await tester.pumpWidget(_wrapFa(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('تحلیل و پردازش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحلیل و پردازش'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ابتدا یک نمونه پیش‌فرض انتخاب کنید'), findsOneWidget);
  });

  testWidgets('About screen renders in Persian correctly', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    appLocaleNotifier.value = const Locale('fa');
    await tester.pumpWidget(_wrapFa(const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('درباره برنامه'), findsOneWidget);
    expect(find.text('V2.0.0'), findsOneWidget);
    expect(find.textContaining('MIT-BIH'), findsOneWidget);
    expect(find.text('0.965'), findsOneWidget);
    expect(find.textContaining('پروژه آموزشی و پژوهشی'), findsOneWidget);
  });
}
