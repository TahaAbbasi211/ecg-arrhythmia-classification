import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/analysis_worker.dart';
import '../l10n/strings.dart';
import 'theme.dart';

/// Lowest and highest sample that fall into one pixel column.
class ColumnEnvelope {
  ColumnEnvelope(this.min, this.max);

  double min;
  double max;
}

/// Hospital-grade ECG strip painter with clinical millimeter paper grid,
/// min-max envelope decimation, phosphor glow, beat badges, and live sweep cursor.
class EcgTracePainter extends CustomPainter {
  EcgTracePainter({
    required this.payload,
    required this.scrollController,
    required this.windowSeconds,
    required this.gridColor,
    required this.traceColor,
    this.majorGridColor,
    this.traceGlowColor,
    this.playheadColor,
    this.palette,
    this.selectedBeatIndex,
    this.playheadSample,
  }) : super(repaint: scrollController);

  final AnalysisPayload payload;
  final ScrollController scrollController;
  final double windowSeconds;
  final Color gridColor;
  final Color? majorGridColor;
  final Color traceColor;
  final Color? traceGlowColor;
  final Color? playheadColor;
  final BioVantaPalette? palette;
  final int? selectedBeatIndex;
  final double? playheadSample;

  double contentWidth(double viewportWidth) {
    final fs = payload.sampleRate.toDouble();
    if (fs <= 0 || payload.signal.isEmpty) return viewportWidth;
    final totalSeconds = payload.signal.length / fs;
    return math.max(viewportWidth, totalSeconds * viewportWidth / windowSeconds);
  }

  double pxPerSampleFor(double viewportWidth) {
    if (payload.signal.isEmpty) return 0;
    return contentWidth(viewportWidth) / payload.signal.length;
  }

  double xForSample(int sample, double viewportWidth) =>
      sample * pxPerSampleFor(viewportWidth);

  /// Collapse [signal] into one min/max pair per pixel column so no spike
  /// can vanish between pixels when zoomed out.
  static List<ColumnEnvelope?> envelope(
    List<double> signal, {
    required double pxPerSample,
    required double offset,
    required int columns,
  }) {
    final out = List<ColumnEnvelope?>.filled(columns, null);
    if (pxPerSample <= 0 || columns <= 0 || signal.isEmpty) return out;

    final first = math.max(0, (offset / pxPerSample).floor());
    final last = math.min(
      signal.length,
      ((offset + columns) / pxPerSample).ceil() + 1,
    );
    for (var i = first; i < last; i++) {
      final column = (i * pxPerSample - offset).floor();
      if (column < 0 || column >= columns) continue;
      final value = signal[i];
      final current = out[column];
      if (current == null) {
        out[column] = ColumnEnvelope(value, value);
      } else {
        if (value < current.min) current.min = value;
        if (value > current.max) current.max = value;
      }
    }
    return out;
  }

  double? _fallbackLo;
  double? _fallbackHi;

  void _ensureFallbackRange() {
    if (_fallbackLo != null) return;
    var lo = payload.signal.isEmpty ? 0.0 : payload.signal[0];
    var hi = lo;
    for (final value in payload.signal) {
      if (value < lo) lo = value;
      if (value > hi) hi = value;
    }
    _fallbackLo = lo;
    _fallbackHi = hi;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final signal = payload.signal;
    if (signal.isEmpty || size.width <= 0 || size.height <= 0) return;

    final fs = payload.sampleRate.toDouble();
    final pxPerSample = pxPerSampleFor(size.width);
    if (pxPerSample <= 0) return;
    final pxPerSecond = pxPerSample * fs;

    final content = contentWidth(size.width);
    final maxOffset = math.max(0.0, content - size.width);
    final offset = scrollController.hasClients
        ? scrollController.offset.clamp(0.0, maxOffset)
        : 0.0;

    var lo = payload.p1;
    var hi = payload.p99;
    if (!(hi > lo)) {
      _ensureFallbackRange();
      lo = _fallbackLo!;
      hi = _fallbackHi!;
    }
    final span = math.max(hi - lo, 1e-6);
    const top = 16.0;
    const bottomPad = 18.0;
    final plotHeight = math.max(size.height - top - bottomPad, 1.0);
    double yFor(double value) {
      final y = top + (hi - value) / span * plotHeight;
      return y.clamp(top - 4.0, size.height - bottomPad + 4.0);
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final minorPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    final majorPaint = Paint()
      ..color = majorGridColor ?? gridColor
      ..strokeWidth = 1.0;
    final secPaint = Paint()
      ..color = (majorGridColor ?? gridColor).withValues(alpha: 0.85)
      ..strokeWidth = 1.25;

    // ECG millimeter grid: 40 ms minor (when wide enough) and 200 ms major boxes.
    final pxPer200ms = pxPerSecond * 0.2;
    final pxPer40ms = pxPerSecond * 0.04;
    final draw40ms = pxPer40ms >= 4.0;
    final draw200ms = pxPer200ms >= 6.0;

    if (draw40ms) {
      final firstTick = (offset / pxPer40ms).floor();
      final lastTick = ((offset + size.width) / pxPer40ms).ceil();
      for (var t = math.max(0, firstTick); t <= lastTick; t++) {
        if (t % 5 == 0) continue;
        final x = t * pxPer40ms - offset;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
      }
    }
    if (draw200ms) {
      final firstMajor = (offset / pxPer200ms).floor();
      final lastMajor = ((offset + size.width) / pxPer200ms).ceil();
      for (var t = math.max(0, firstMajor); t <= lastMajor; t++) {
        final x = t * pxPer200ms - offset;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          t % 5 == 0 ? secPaint : majorPaint,
        );
      }
    }

    // Horizontal millimeter amplitude grid + centerline
    final horizStep = size.height / 8.0;
    for (var r = 1; r < 8; r++) {
      final y = r * horizStep;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        r == 4 ? majorPaint : minorPaint,
      );
    }

    // Time ticks along the bottom strip
    final tickEverySeconds = windowSeconds > 12 ? 2 : 1;
    final firstSec = (offset / pxPerSecond).floor();
    final lastSec = ((offset + size.width) / pxPerSecond).ceil();
    final labelStyle = TextStyle(
      fontSize: 9.5,
      color: (palette?.textMuted ?? gridColor).withValues(alpha: 0.9),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (var sec = math.max(0, firstSec); sec <= lastSec; sec++) {
      if (sec % tickEverySeconds != 0) continue;
      final x = sec * pxPerSecond - offset;
      if (x < 0 || x > size.width - 18) continue;
      final tp = TextPainter(
        text: TextSpan(text: '${sec}s', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, size.height - 13));
    }

    // Waveform path
    final Path tracePath;
    if (pxPerSample >= 1.0) {
      final first = math.max(0, (offset / pxPerSample).floor());
      final last = math.min(
        signal.length,
        ((offset + size.width) / pxPerSample).ceil() + 1,
      );
      final path = Path();
      var started = false;
      for (var i = first; i < last; i++) {
        final x = i * pxPerSample - offset;
        final y = yFor(signal[i]);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      tracePath = path;
    } else {
      final columns = size.width.ceil();
      final envelope = EcgTracePainter.envelope(
        signal,
        pxPerSample: pxPerSample,
        offset: offset,
        columns: columns,
      );
      final path = Path();
      var started = false;
      for (var column = 0; column < columns; column++) {
        final band = envelope[column];
        if (band == null) continue;
        final x = column + 0.5;
        if (!started) {
          path.moveTo(x, yFor(band.max));
          started = true;
        }
        path.lineTo(x, yFor(band.max));
        path.lineTo(x, yFor(band.min));
      }
      tracePath = path;
    }

    if (traceGlowColor != null && traceGlowColor!.a > 0) {
      canvas.drawPath(
        tracePath,
        Paint()
          ..color = traceGlowColor!
          ..strokeWidth = 3.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      tracePath,
      Paint()
        ..color = traceColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Beat markers + selected halo
    final markerPaint = Paint()..strokeWidth = 1.4;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final sortedPeaks = List<int>.generate(payload.peaks.length, (i) => i)
      ..sort((a, b) => payload.peaks[a].compareTo(payload.peaks[b]));

    for (var rank = 0; rank < sortedPeaks.length; rank++) {
      final orig = sortedPeaks[rank];
      final peak = payload.peaks[orig];
      if (peak < 0 || peak >= signal.length) continue;
      final x = peak * pxPerSample - offset;
      if (x < -8 || x > size.width + 8) continue;

      final cls = payload.pred[orig];
      final color = palette?.colorForClass(cls) ?? colorForClass(cls);
      final y = yFor(signal[peak]);
      final isSelected = selectedBeatIndex == rank || selectedBeatIndex == orig;
      final isAbnormal = cls == 1 || cls == 2;

      if (isSelected) {
        canvas.drawRect(
          Rect.fromLTWH(x - 10, 0, 20, size.height),
          Paint()..color = color.withValues(alpha: 0.12),
        );
      }

      markerPaint
        ..color = color.withValues(alpha: isSelected ? 0.9 : (isAbnormal ? 0.65 : 0.36))
        ..strokeWidth = isSelected ? 2.0 : 1.3;
      canvas.drawLine(Offset(x, top - 2), Offset(x, size.height - bottomPad + 2), markerPaint);

      dotPaint.color = color;
      canvas.drawCircle(Offset(x, y), isSelected ? 4.4 : 2.8, dotPaint);

      if (isSelected || isAbnormal || windowSeconds <= 10) {
        final badgeTp = TextPainter(
          text: TextSpan(
            text: classLabels[cls],
            style: TextStyle(
              fontSize: isSelected ? 10 : 8.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        badgeTp.paint(canvas, Offset(x - badgeTp.width / 2, 2));
      }
    }

    // Live sweep playhead cursor
    if (playheadSample != null && playheadSample! >= 0) {
      final px = playheadSample! * pxPerSample - offset;
      if (px >= -2 && px <= size.width + 2) {
        final pColor = playheadColor ?? palette?.cyan ?? const Color(0xFF39C5CF);
        canvas.drawLine(
          Offset(px, 0),
          Offset(px, size.height),
          Paint()
            ..color = pColor.withValues(alpha: 0.35)
            ..strokeWidth = 5.0,
        );
        canvas.drawLine(
          Offset(px, 0),
          Offset(px, size.height),
          Paint()
            ..color = pColor
            ..strokeWidth = 2.0,
        );
        final tri = Path()
          ..moveTo(px - 5, 0)
          ..lineTo(px + 5, 0)
          ..lineTo(px, 7)
          ..close();
        canvas.drawPath(tri, Paint()..color = pColor);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EcgTracePainter old) {
    return old.payload != payload ||
        old.windowSeconds != windowSeconds ||
        old.traceColor != traceColor ||
        old.gridColor != gridColor ||
        old.majorGridColor != majorGridColor ||
        old.traceGlowColor != traceGlowColor ||
        old.selectedBeatIndex != selectedBeatIndex ||
        old.playheadSample != playheadSample ||
        old.palette != palette;
  }
}

/// Interactive horizontally scrollable ECG plot with optional beat tap selection
/// and live playback sweep cursor. Always scrolls left-to-right regardless of locale.
class EcgPlot extends StatefulWidget {
  const EcgPlot({
    super.key,
    required this.payload,
    required this.windowSeconds,
    required this.scrollController,
    this.selectedBeatIndex,
    this.playheadSample,
    this.onBeatSelected,
  });

  final AnalysisPayload payload;
  final double windowSeconds;
  final ScrollController scrollController;
  final int? selectedBeatIndex;
  final double? playheadSample;
  final ValueChanged<int>? onBeatSelected;

  @override
  State<EcgPlot> createState() => _EcgPlotState();
}

class _EcgPlotState extends State<EcgPlot> {
  void _handleTapUp(TapUpDetails details, double viewportWidth) {
    final cb = widget.onBeatSelected;
    if (cb == null || widget.payload.peaks.isEmpty) return;

    final fs = widget.payload.sampleRate.toDouble();
    final totalSamples = widget.payload.signal.length;
    if (fs <= 0 || totalSamples <= 0 || viewportWidth <= 0) return;

    final totalSeconds = totalSamples / fs;
    final contentWidth = math.max(
      viewportWidth,
      totalSeconds * viewportWidth / widget.windowSeconds,
    );
    final pxPerSample = contentWidth / totalSamples;
    if (pxPerSample <= 0) return;

    final offset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final tappedSample = (details.localPosition.dx + offset) / pxPerSample;
    final maxDistSamples = 28.0 / pxPerSample;

    final order = List<int>.generate(widget.payload.peaks.length, (i) => i)
      ..sort((a, b) => widget.payload.peaks[a].compareTo(widget.payload.peaks[b]));

    var bestRank = -1;
    var bestDist = double.infinity;
    for (var rank = 0; rank < order.length; rank++) {
      final sample = widget.payload.peaks[order[rank]];
      final dist = (sample - tappedSample).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestRank = rank;
      }
    }

    if (bestRank >= 0 && bestDist <= maxDistSamples) {
      HapticFeedback.selectionClick();
      cb(bestRank);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final fs = widget.payload.sampleRate.toDouble();
    final totalSeconds = fs > 0 ? widget.payload.signal.length / fs : 0.0;

    return Container(
      color: pal.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = math.max(constraints.maxWidth, 1.0);
          final height = math.max(constraints.maxHeight, 1.0);
          final pxPerSecond = viewport / widget.windowSeconds;
          final totalWidth = math.max(viewport, totalSeconds * pxPerSecond);

          return Directionality(
            // Always left-to-right in time even when the UI locale is Persian RTL.
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: widget.onBeatSelected == null
                  ? null
                  : (details) => _handleTapUp(details, viewport),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: EcgTracePainter(
                          payload: widget.payload,
                          scrollController: widget.scrollController,
                          windowSeconds: widget.windowSeconds,
                          gridColor: pal.gridMinor,
                          majorGridColor: pal.gridMajor,
                          traceColor: pal.trace,
                          traceGlowColor: pal.traceGlow,
                          playheadColor: pal.cyan,
                          palette: pal,
                          selectedBeatIndex: widget.selectedBeatIndex,
                          playheadSample: widget.playheadSample,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: SingleChildScrollView(
                      controller: widget.scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(width: totalWidth, height: height),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Legend for the beat marker colors.
class EcgLegend extends StatelessWidget {
  const EcgLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: pal.textMuted,
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (var i = 0; i < 3; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: pal.colorForClass(i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${classLabels[i]} · ${s.classLabelLong(i)}',
                  style: textStyle,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
