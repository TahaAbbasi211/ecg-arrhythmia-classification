import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/analysis_worker.dart';
import '../l10n/strings.dart';
import 'theme.dart';

/// Lowest and highest sample that fall into one pixel column.
class ColumnEnvelope {
  ColumnEnvelope(this.min, this.max);

  double min;
  double max;
}

/// Draws the visible part of the filtered ECG, one column at a time.
///
/// The painter never sees the scrollable content: it paints the viewport only
/// and reads the scroll offset from [scrollController], which also triggers
/// repaints. That keeps a 30 minute recording as cheap to scroll as a 10 s one.
class EcgTracePainter extends CustomPainter {
  EcgTracePainter({
    required this.payload,
    required this.scrollController,
    required this.windowSeconds,
    required this.gridColor,
    required this.traceColor,
    required this.markerLabelColor,
  }) : super(repaint: scrollController);

  final AnalysisPayload payload;

  /// Drives both the offset and the repaint.
  final ScrollController scrollController;

  /// Visible window width in seconds.
  final double windowSeconds;
  final Color gridColor;
  final Color traceColor;
  final Color markerLabelColor;

  /// Total width of the scrollable content for a [viewportWidth] wide plot.
  ///
  /// This, not the viewport, sets pixels per sample: 60 s at 360 Hz on a 400 px
  /// viewport with an 8 s window is 3000 px of content, so 0.139 px per sample.
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

  /// Collapse [signal] into one min/max pair per pixel column.
  ///
  /// Min-Max decimation keeps the extreme sample of every column, so a spike
  /// that is 7 samples wide still shows when 7 samples share one pixel.
  static List<ColumnEnvelope?> envelope(
    List<double> signal, {
    required double pxPerSample,
    required double offset,
    required int columns,
  }) {
    final out = List<ColumnEnvelope?>.filled(columns, null);
    if (pxPerSample <= 0 || columns <= 0 || signal.isEmpty) return out;

    // Sample i lands in column floor(i * pxPerSample - offset), so column
    // `columns - 1` ends at sample (offset + columns) / pxPerSample.
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

    // Vertical scale from the 1st/99th percentile of the filtered signal, so a
    // single spike cannot squash the whole trace.
    var lo = payload.p1;
    var hi = payload.p99;
    if (!(hi > lo)) {
      _ensureFallbackRange();
      lo = _fallbackLo!;
      hi = _fallbackHi!;
    }
    final span = math.max(hi - lo, 1e-6);
    final top = 8.0;
    final plotHeight = math.max(size.height - 16.0, 1.0);
    double yFor(double value) {
      final y = top + (hi - value) / span * plotHeight;
      return y.clamp(2.0, size.height - 2.0);
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Grid: one vertical line per second, plus a midline.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    final firstSecond = (offset / pxPerSecond).floor();
    final lastSecond = ((offset + size.width) / pxPerSecond).ceil();
    for (var second = math.max(0, firstSecond);
        second <= lastSecond;
        second++) {
      final x = second * pxPerSecond - offset;
      if (x < -1 || x > size.width + 1) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    final tracePaint = Paint()
      ..color = traceColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    if (pxPerSample >= 1.0) {
      // Zoomed in: one point per sample is both cheaper and more accurate.
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
      canvas.drawPath(path, tracePaint);
    } else {
      // Min-Max envelope: every pixel column draws the true extremes of the
      // samples behind it, so no beat can disappear between two pixels.
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
      canvas.drawPath(path, tracePaint);
    }

    // Beat markers, only for the visible range.
    final markerPaint = Paint()..strokeWidth = 1.6;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var b = 0; b < payload.peaks.length; b++) {
      final peak = payload.peaks[b];
      if (peak < 0 || peak >= signal.length) continue;
      final x = peak * pxPerSample - offset;
      if (x < -4 || x > size.width + 4) continue;
      final color = colorForClass(payload.pred[b]);
      final y = yFor(signal[peak]);
      markerPaint.color = color.withValues(alpha: 0.55);
      dotPaint.color = color;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EcgTracePainter old) {
    return old.payload != payload ||
        old.windowSeconds != windowSeconds ||
        old.traceColor != traceColor ||
        old.gridColor != gridColor;
  }
}

/// Horizontally scrollable ECG plot with a fixed visible window.
///
/// The painter sits behind a transparent scroll view: the scroll view owns the
/// gesture and the content width, the painter only redraws the visible window.
class EcgPlot extends StatefulWidget {
  const EcgPlot({
    super.key,
    required this.payload,
    required this.windowSeconds,
    required this.scrollController,
  });

  final AnalysisPayload payload;
  final double windowSeconds;
  final ScrollController scrollController;

  @override
  State<EcgPlot> createState() => _EcgPlotState();
}

class _EcgPlotState extends State<EcgPlot> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fs = widget.payload.sampleRate.toDouble();
    final totalSeconds = fs > 0 ? widget.payload.signal.length / fs : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = math.max(constraints.maxWidth, 1.0);
        final height = math.max(constraints.maxHeight, 1.0);
        final pxPerSecond = viewport / widget.windowSeconds;
        final totalWidth = math.max(viewport, totalSeconds * pxPerSecond);

        return Directionality(
          // A Persian locale flips the scroll axis and would scroll the wrong
          // way at offset 0; the plot is always left to right in time.
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: EcgTracePainter(
                      payload: widget.payload,
                      scrollController: widget.scrollController,
                      windowSeconds: widget.windowSeconds,
                      gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
                      traceColor: scheme.onSurface.withValues(alpha: 0.85),
                      markerLabelColor: scheme.onSurface,
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
        );
      },
    );
  }
}

/// Legend for the beat marker colors.
class EcgLegend extends StatelessWidget {
  const EcgLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final textStyle = Theme.of(context).textTheme.labelMedium;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (var i = 0; i < 3; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorForClass(i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              // At 320 px a Persian label is wider than the screen.
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