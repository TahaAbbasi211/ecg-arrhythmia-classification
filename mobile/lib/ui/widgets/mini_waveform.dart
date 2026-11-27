import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Signature mini-ECG silhouette shown inside each bundled MIT-BIH record card.
class MiniWaveform extends StatelessWidget {
  const MiniWaveform({
    super.key,
    required this.recordId,
    required this.accentColor,
    this.height = 42,
  });

  final String recordId;
  final Color accentColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: _MiniWavePainter(
            recordId: recordId,
            accentColor: accentColor,
            gridColor: pal.border.withValues(alpha: 0.55),
            glow: pal.isDark,
          ),
        ),
      ),
    );
  }
}

class _MiniWavePainter extends CustomPainter {
  _MiniWavePainter({
    required this.recordId,
    required this.accentColor,
    required this.gridColor,
    required this.glow,
  });

  final String recordId;
  final Color accentColor;
  final Color gridColor;
  final bool glow;

  static double _gauss(double x, double mu, double sigma, double amp) {
    final z = (x - mu) / sigma;
    return amp * math.exp(-z * z);
  }

  double _valueAt(double x) {
    if (recordId == '200') {
      // Sinus beat -> wide premature ventricular beat (PVC) -> sinus beat
      return _gauss(x, 0.13, 0.018, 0.14) +
          _gauss(x, 0.21, 0.011, 0.86) +
          _gauss(x, 0.23, 0.010, -0.22) +
          _gauss(x, 0.31, 0.032, 0.22) +
          // PVC complex
          _gauss(x, 0.49, 0.022, 0.96) +
          _gauss(x, 0.54, 0.026, -0.58) +
          _gauss(x, 0.62, 0.035, 0.20) +
          // Recovery sinus
          _gauss(x, 0.80, 0.012, 0.82) +
          _gauss(x, 0.82, 0.011, -0.20) +
          _gauss(x, 0.90, 0.030, 0.20);
    }
    if (recordId == '233') {
      // Mixed early supraventricular beat + ventricular beat
      return _gauss(x, 0.15, 0.011, 0.85) +
          _gauss(x, 0.17, 0.010, -0.20) +
          _gauss(x, 0.25, 0.028, 0.20) +
          // Early S beat
          _gauss(x, 0.37, 0.011, 0.78) +
          _gauss(x, 0.44, 0.026, 0.18) +
          // V beat
          _gauss(x, 0.63, 0.021, 0.94) +
          _gauss(x, 0.68, 0.025, -0.52) +
          _gauss(x, 0.85, 0.012, 0.80);
    }
    // Regular clean normal sinus rhythm (Record 100)
    var y = 0.0;
    for (final center in const [0.18, 0.50, 0.82]) {
      y += _gauss(x, center - 0.07, 0.020, 0.14) +
          _gauss(x, center - 0.02, 0.008, -0.14) +
          _gauss(x, center, 0.010, 0.92) +
          _gauss(x, center + 0.02, 0.010, -0.24) +
          _gauss(x, center + 0.09, 0.028, 0.24);
    }
    return y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final baseline = size.height * 0.66;
    final scale = size.height * 0.54;

    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = gridColor
        ..strokeWidth = 0.8,
    );

    final path = Path();
    const n = 96;
    for (var i = 0; i <= n; i++) {
      final x = i / n;
      final px = x * size.width;
      final py = baseline - _valueAt(x) * scale;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = accentColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniWavePainter old) {
    return old.recordId != recordId ||
        old.accentColor != accentColor ||
        old.glow != glow;
  }
}
