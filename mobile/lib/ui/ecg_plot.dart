import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/analysis_worker.dart';
import 'theme.dart';

/// Draws the filtered ECG trace with colored beat markers.
class EcgTracePainter extends CustomPainter {
  EcgTracePainter({
    required this.payload,
    required this.windowSeconds,
    required this.gridColor,
    required this.traceColor,
    required this.markerLabelColor,
  });

  final AnalysisPayload payload;

  /// Visible window width in seconds; the painter receives the matching width.
  final double windowSeconds;
  final Color gridColor;
  final Color traceColor;
  final Color markerLabelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final signal = payload.signal;
    if (signal.isEmpty || size.width <= 0) return;

    final fs = payload.sampleRate.toDouble();
    final pxPerSample = size.width / (windowSeconds * fs);

    // Vertical scaling from the signal's own range, with a little headroom.
    var lo = signal[0];
    var hi = signal[0];
    for (final v in signal) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = math.max(hi - lo, 1e-6);
    final top = 8.0;
    final plotHeight = math.max(size.height - 16.0, 1.0);
    double yFor(double v) => top + (hi - v) / span * plotHeight;

    // Grid: one vertical line per second, one horizontal midline.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    final seconds = (size.width / (pxPerSample * fs));
    for (var s = 0.0; s <= seconds; s += 1.0) {
      final x = s * fs * pxPerSample;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Trace: one polyline over the whole signal, clipped to the visible width.
    final tracePaint = Paint()
      ..color = traceColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final step = pxPerSample < 0.5 ? 1 : math.max(1, (0.5 / pxPerSample).floor());
    var started = false;
    for (var i = 0; i < signal.length; i += step) {
      final x = i * pxPerSample;
      final y = yFor(signal[i]);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, tracePaint);

    // Beat markers.
    final markerPaint = Paint()..strokeWidth = 1.6;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var b = 0; b < payload.peaks.length; b++) {
      final p = payload.peaks[b];
      if (p < 0 || p >= signal.length) continue;
      final x = p * pxPerSample;
      final y = yFor(signal[p]);
      final color = colorForClass(payload.pred[b]);
      markerPaint.color = color.withValues(alpha: 0.55);
      dotPaint.color = color;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }
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
    final totalSeconds = widget.payload.signal.length / fs;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final pxPerSecond = viewport / widget.windowSeconds;
        final totalWidth = math.max(viewport, totalSeconds * pxPerSecond);

        return SingleChildScrollView(
          controller: widget.scrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            height: constraints.maxHeight,
            child: CustomPaint(
              painter: EcgTracePainter(
                payload: widget.payload,
                windowSeconds: widget.windowSeconds,
                gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
                traceColor: scheme.onSurface.withValues(alpha: 0.85),
                markerLabelColor: scheme.onSurface,
              ),
            ),
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
              Text('${classLabels[i]} · ${classLongLabels[i]}', style: textStyle),
            ],
          ),
      ],
    );
  }
}
