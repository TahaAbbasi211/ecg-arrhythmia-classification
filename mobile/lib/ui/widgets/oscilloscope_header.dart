import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../theme.dart';

/// Alive 60fps synthetic P-QRS-T cardiac monitor stage for the Monitor tab.
class OscilloscopeHeader extends StatefulWidget {
  const OscilloscopeHeader({
    super.key,
    this.animate,
  });

  /// Explicit override; defaults to true on devices and false under `flutter_test`
  /// so continuous animations never stall `pumpAndSettle`.
  final bool? animate;

  @override
  State<OscilloscopeHeader> createState() => _OscilloscopeHeaderState();
}

class _OscilloscopeHeaderState extends State<OscilloscopeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
      value: 0.72,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant OscilloscopeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final disableAnims = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final inWidgetTest = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
    final shouldAnimate = widget.animate ?? (!disableAnims && !inWidgetTest);
    if (shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0.72;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cycleTheme() {
    final cur = appThemeModeNotifier.value;
    appThemeModeNotifier.value =
        cur == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void _toggleLocale() {
    final cur = appLocaleNotifier.value.languageCode;
    appLocaleNotifier.value =
        cur == 'fa' ? const Locale('en') : const Locale('fa');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: pal.borderAccent),
        boxShadow: pal.isDark
            ? [
                BoxShadow(
                  color: pal.cyan.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: pal.normalN,
                    shape: BoxShape.circle,
                    boxShadow: pal.isDark
                        ? [
                            BoxShadow(
                              color: pal.normalN.withValues(alpha: 0.7),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        s.brandName,
                        style: tabularStyle(
                          theme.textTheme.labelLarge,
                          color: pal.textPrimary,
                          fontWeight: FontWeight.w800,
                          monospace: true,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: pal.cyan.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: pal.cyan.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          s.appVersion,
                          style: tabularStyle(
                            theme.textTheme.labelSmall,
                            color: pal.cyan,
                            fontWeight: FontWeight.w700,
                            monospace: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: s.themeTooltip,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: pal.elevated,
                    foregroundColor: pal.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: pal.border),
                    ),
                  ),
                  icon: Icon(
                    pal.isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 18,
                  ),
                  onPressed: _cycleTheme,
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: s.languageTooltip,
                  child: InkWell(
                    onTap: _toggleLocale,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: pal.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: pal.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.translate, size: 15, color: pal.cyan),
                          const SizedBox(width: 4),
                          Text(
                            s.languageToggle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 112,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: CustomPaint(
                painter: _OscilloscopePainter(
                  phaseListenable: _controller,
                  palette: pal,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
            decoration: BoxDecoration(
              color: pal.elevated.withValues(alpha: 0.65),
              border: Border(top: BorderSide(color: pal.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 14, color: pal.normalN),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.heroStatusPill,
                    style: tabularStyle(
                      theme.textTheme.labelMedium,
                      color: pal.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'LEAD II · 360 Hz',
                  style: tabularStyle(
                    theme.textTheme.labelSmall,
                    color: pal.cyan,
                    fontWeight: FontWeight.w700,
                    monospace: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OscilloscopePainter extends CustomPainter {
  _OscilloscopePainter({
    required this.phaseListenable,
    required this.palette,
  }) : super(repaint: phaseListenable);

  final Animation<double> phaseListenable;
  final BioVantaPalette palette;

  static double _gauss(double t, double center, double width, double amp) {
    final z = (t - center) / width;
    return amp * math.exp(-z * z);
  }

  /// Continuous physiological P-QRS-T synthetic cycle in [0, 1].
  static double _beatSample(double u) {
    return _gauss(u, 0.19, 0.036, 0.14) + // P wave
        _gauss(u, 0.35, 0.011, -0.15) + // Q dip
        _gauss(u, 0.38, 0.014, 0.96) + // R spike
        _gauss(u, 0.415, 0.013, -0.27) + // S dip
        _gauss(u, 0.63, 0.055, 0.25); // T wave
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Millimeter paper grid
    final minorPaint = Paint()
      ..color = palette.gridMinor
      ..strokeWidth = 0.8;
    final majorPaint = Paint()
      ..color = palette.gridMajor
      ..strokeWidth = 1.1;

    const minorStep = 12.0;
    for (var x = 0.0, col = 0; x <= size.width; x += minorStep, col++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        col % 5 == 0 ? majorPaint : minorPaint,
      );
    }
    for (var y = 0.0, row = 0; y <= size.height; y += minorStep, row++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        row % 4 == 0 ? majorPaint : minorPaint,
      );
    }

    final head = phaseListenable.value.clamp(0.0, 1.0);
    const steps = 220;
    final baselineY = size.height * 0.64;
    final ampScale = size.height * 0.48;
    const gapSpan = 0.055;

    final points = <Offset>[];
    final ages = <double>[];

    for (var i = 0; i <= steps; i++) {
      final frac = i / steps;
      // Age from sweep cursor (0 = just drawn at head, 1 = oldest before head).
      final age = (head - frac + 1.0) % 1.0;
      if (age > 1.0 - gapSpan) continue;
      // 3 cardiac cycles visible across the scope width
      final cycleU = (frac * 3.0) % 1.0;
      final v = _beatSample(cycleU);
      points.add(Offset(frac * size.width, baselineY - v * ampScale));
      ages.add(age);
    }

    // Break polyline wherever erasure gap crosses segment
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i < points.length; i++) {
      if ((points[i].dx - points[i - 1].dx).abs() > size.width * 0.05) {
        continue;
      }
      final freshness = (1.0 - ages[i]).clamp(0.15, 1.0);
      if (palette.isDark) {
        glowPaint.color = palette.traceGlow.withValues(alpha: 0.42 * freshness);
        canvas.drawLine(points[i - 1], points[i], glowPaint);
      }
      linePaint.color = palette.trace.withValues(alpha: 0.25 + 0.75 * freshness);
      canvas.drawLine(points[i - 1], points[i], linePaint);
    }

    // Phosphor leading cursor dot
    final headCycle = (head * 3.0) % 1.0;
    final headOffset = Offset(
      head * size.width,
      baselineY - _beatSample(headCycle) * ampScale,
    );
    if (palette.isDark) {
      canvas.drawCircle(
        headOffset,
        7.0,
        Paint()..color = palette.cyan.withValues(alpha: 0.28),
      );
    }
    canvas.drawCircle(
      headOffset,
      3.4,
      Paint()..color = palette.isDark ? palette.cyan : palette.normalN,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OscilloscopePainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}
