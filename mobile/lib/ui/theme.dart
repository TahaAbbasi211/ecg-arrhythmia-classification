/// BioVanta Obsidian Dark & Clinical Paper Light themes and semantic tokens.
library;

import 'package:flutter/material.dart';

/// Global theme mode notifier so the user can toggle Dark / Light / System anywhere.
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.dark,
);

/// Default flagship phosphor beat colors (also adapted per brightness in [BioVantaPalette]).
const Color classNColor = Color(0xFF3FB950);
const Color classSColor = Color(0xFFF5A623);
const Color classVColor = Color(0xFFFF4D5E);
const Color classFColor = Color(0xFF6E7781);

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

@immutable
class BioVantaPalette extends ThemeExtension<BioVantaPalette> {
  const BioVantaPalette({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.elevated,
    required this.border,
    required this.borderAccent,
    required this.textPrimary,
    required this.textMuted,
    required this.normalN,
    required this.supraS,
    required this.ventricV,
    required this.cyan,
    required this.fusionF,
    required this.gridMinor,
    required this.gridMajor,
    required this.trace,
    required this.traceGlow,
    required this.dockBg,
  });

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color elevated;
  final Color border;
  final Color borderAccent;
  final Color textPrimary;
  final Color textMuted;
  final Color normalN;
  final Color supraS;
  final Color ventricV;
  final Color cyan;
  final Color fusionF;
  final Color gridMinor;
  final Color gridMajor;
  final Color trace;
  final Color traceGlow;
  final Color dockBg;

  static const BioVantaPalette dark = BioVantaPalette(
    isDark: true,
    canvas: Color(0xFF07090C),
    surface: Color(0xFF0F131B),
    elevated: Color(0xFF151B26),
    border: Color(0xFF1F2937),
    borderAccent: Color(0xFF2D3A4F),
    textPrimary: Color(0xFFE6EDF3),
    textMuted: Color(0xFF8B949E),
    normalN: Color(0xFF3FB950),
    supraS: Color(0xFFF5A623),
    ventricV: Color(0xFFFF4D5E),
    cyan: Color(0xFF39C5CF),
    fusionF: Color(0xFF6E7781),
    gridMinor: Color(0x1639C5CF),
    gridMajor: Color(0x3339C5CF),
    trace: Color(0xFF5CE6A0),
    traceGlow: Color(0x553FB950),
    dockBg: Color(0xEB0F131B),
  );

  static const BioVantaPalette light = BioVantaPalette(
    isDark: false,
    canvas: Color(0xFFF6F3EC),
    surface: Color(0xFFFDFBF7),
    elevated: Color(0xFFECE7DC),
    border: Color(0xFFD8D1C2),
    borderAccent: Color(0xFFBFB6A3),
    textPrimary: Color(0xFF1A1E24),
    textMuted: Color(0xFF5C6470),
    normalN: Color(0xFF0F7A3D),
    supraS: Color(0xFFB45309),
    ventricV: Color(0xFFC81E32),
    cyan: Color(0xFF0E7490),
    fusionF: Color(0xFF6E7781),
    gridMinor: Color.fromRGBO(198, 90, 90, 0.14),
    gridMajor: Color.fromRGBO(198, 90, 90, 0.26),
    trace: Color(0xFF1A1E24),
    traceGlow: Colors.transparent,
    dockBg: Color(0xF0FDFBF7),
  );

  static BioVantaPalette of(BuildContext context) {
    final ext = Theme.of(context).extension<BioVantaPalette>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  Color colorForClass(int index) {
    switch (index) {
      case 0:
        return normalN;
      case 1:
        return supraS;
      case 2:
        return ventricV;
      default:
        return fusionF;
    }
  }

  @override
  BioVantaPalette copyWith({
    bool? isDark,
    Color? canvas,
    Color? surface,
    Color? elevated,
    Color? border,
    Color? borderAccent,
    Color? textPrimary,
    Color? textMuted,
    Color? normalN,
    Color? supraS,
    Color? ventricV,
    Color? cyan,
    Color? fusionF,
    Color? gridMinor,
    Color? gridMajor,
    Color? trace,
    Color? traceGlow,
    Color? dockBg,
  }) {
    return BioVantaPalette(
      isDark: isDark ?? this.isDark,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      elevated: elevated ?? this.elevated,
      border: border ?? this.border,
      borderAccent: borderAccent ?? this.borderAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      normalN: normalN ?? this.normalN,
      supraS: supraS ?? this.supraS,
      ventricV: ventricV ?? this.ventricV,
      cyan: cyan ?? this.cyan,
      fusionF: fusionF ?? this.fusionF,
      gridMinor: gridMinor ?? this.gridMinor,
      gridMajor: gridMajor ?? this.gridMajor,
      trace: trace ?? this.trace,
      traceGlow: traceGlow ?? this.traceGlow,
      dockBg: dockBg ?? this.dockBg,
    );
  }

  @override
  BioVantaPalette lerp(ThemeExtension<BioVantaPalette>? other, double t) {
    if (other is! BioVantaPalette) return this;
    return BioVantaPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderAccent: Color.lerp(borderAccent, other.borderAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      normalN: Color.lerp(normalN, other.normalN, t)!,
      supraS: Color.lerp(supraS, other.supraS, t)!,
      ventricV: Color.lerp(ventricV, other.ventricV, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      fusionF: Color.lerp(fusionF, other.fusionF, t)!,
      gridMinor: Color.lerp(gridMinor, other.gridMinor, t)!,
      gridMajor: Color.lerp(gridMajor, other.gridMajor, t)!,
      trace: Color.lerp(trace, other.trace, t)!,
      traceGlow: Color.lerp(traceGlow, other.traceGlow, t)!,
      dockBg: Color.lerp(dockBg, other.dockBg, t)!,
    );
  }
}

/// Shared monospace tabular text style for clinical numbers.
TextStyle tabularStyle(
  TextStyle? base, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  bool monospace = false,
}) {
  return (base ?? const TextStyle()).copyWith(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    fontFamily: monospace ? 'monospace' : null,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final pal = isDark ? BioVantaPalette.dark : BioVantaPalette.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: pal.cyan,
    onPrimary: isDark ? const Color(0xFF041418) : Colors.white,
    primaryContainer: pal.cyan.withValues(alpha: isDark ? 0.16 : 0.12),
    onPrimaryContainer: pal.cyan,
    secondary: pal.normalN,
    onSecondary: isDark ? const Color(0xFF031509) : Colors.white,
    secondaryContainer: pal.normalN.withValues(alpha: isDark ? 0.16 : 0.12),
    onSecondaryContainer: pal.normalN,
    tertiary: pal.supraS,
    onTertiary: isDark ? const Color(0xFF1E1300) : Colors.white,
    error: pal.ventricV,
    onError: isDark ? const Color(0xFF2B0509) : Colors.white,
    errorContainer: pal.ventricV.withValues(alpha: isDark ? 0.16 : 0.11),
    onErrorContainer: isDark ? const Color(0xFFFFB4BC) : const Color(0xFF8C0E1E),
    surface: pal.surface,
    onSurface: pal.textPrimary,
    onSurfaceVariant: pal.textMuted,
    surfaceContainerHighest: pal.elevated,
    outline: pal.borderAccent,
    outlineVariant: pal.border,
  );

  final baseTheme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
  );

  return baseTheme.copyWith(
    scaffoldBackgroundColor: pal.canvas,
    canvasColor: pal.canvas,
    extensions: <ThemeExtension<dynamic>>[pal],
    appBarTheme: AppBarTheme(
      backgroundColor: pal.canvas,
      foregroundColor: pal.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: baseTheme.textTheme.titleMedium?.copyWith(
        color: pal.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: pal.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: pal.border),
      ),
    ),
    dividerTheme: DividerThemeData(color: pal.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pal.elevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.ventricV),
      ),
      labelStyle: TextStyle(color: pal.textMuted),
      helperStyle: TextStyle(color: pal.textMuted, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pal.cyan,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: pal.elevated,
        disabledForegroundColor: pal.textMuted,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.textPrimary,
        backgroundColor: pal.elevated.withValues(alpha: 0.45),
        side: BorderSide(color: pal.borderAccent),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: pal.cyan,
      inactiveTrackColor: pal.borderAccent,
      thumbColor: pal.cyan,
      overlayColor: pal.cyan.withValues(alpha: 0.16),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return pal.canvas;
        return pal.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return pal.cyan;
        return pal.elevated;
      }),
      trackOutlineColor: WidgetStateProperty.all(pal.borderAccent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: pal.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: pal.borderAccent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: pal.elevated,
      contentTextStyle: TextStyle(color: pal.textPrimary, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: pal.borderAccent),
      ),
    ),
  );
}
