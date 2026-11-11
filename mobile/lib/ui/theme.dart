/// Class colors and the app theme.
library;

import 'package:flutter/material.dart';

/// Beat marker colors, fixed by the design brief.
const Color classNColor = Color(0xFF2E9E5B); // green
const Color classSColor = Color(0xFFF0A020); // amber
const Color classVColor = Color(0xFFD63A3A); // red
const Color classFColor = Color(0xFF7A7A7A); // grey, not predicted

const List<Color> classColors = [
  classNColor,
  classSColor,
  classVColor,
  classFColor,
];

const List<String> classLabels = ['N', 'S', 'V', 'F'];

const List<String> classLongLabels = [
  'Normal',
  'Supraventricular',
  'Ventricular',
  'Fusion',
];

Color colorForClass(int index) =>
    index >= 0 && index < classColors.length ? classColors[index] : classFColor;

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E6F9E),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
    ),
  );
}
