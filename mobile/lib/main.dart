import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'ui/instrument_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
  if (systemLocale.languageCode == 'fa') {
    appLocaleNotifier.value = const Locale('fa');
  }
  runApp(const EcgApp());
}

class EcgApp extends StatelessWidget {
  const EcgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeModeNotifier,
          builder: (context, themeMode, _) {
            final platformBrightness =
                WidgetsBinding.instance.platformDispatcher.platformBrightness;
            final isDark = switch (themeMode) {
              ThemeMode.dark => true,
              ThemeMode.light => false,
              ThemeMode.system => platformBrightness == Brightness.dark,
            };
            final overlay = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            );

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlay,
              child: MaterialApp(
                title: 'ECG Beat Classifier',
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(Brightness.light),
                darkTheme: buildAppTheme(Brightness.dark),
                themeMode: themeMode,
                locale: locale,
                supportedLocales: const [
                  Locale('en'),
                  Locale('fa'),
                ],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const InstrumentShell(),
              ),
            );
          },
        );
      },
    );
  }
}
