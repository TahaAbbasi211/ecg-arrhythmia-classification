import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../ecg_view_model.dart';
import '../theme.dart';

/// Beat-to-beat R-R Tachogram & Poincaré HRV scatter plots for the Rhythm sub-tab.
class RhythmAnalyticsView extends StatelessWidget {
  const RhythmAnalyticsView({
    super.key,
    required this.viewModel,
    required this.selectedBeatIndex,
    required this.onSelectBeat,
  });

  final EcgViewModel viewModel;
  final int selectedBeatIndex;
  final ValueChanged<int> onSelectBeat;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);

    if (viewModel.tachogramPoints.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            s.needMoreBeatsForRhythm,
            style: TextStyle(color: pal.textMuted),
          ),
        ),
      );
    }

    final rrMin = viewModel.minRrMs;
    final rrMax = viewModel.maxRrMs;
    final rangeText = (rrMin != null && rrMax != null)
        ? '${rrMin.round()}–${rrMax.round()} ms'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final colWidth = constraints.maxWidth >= 300
                ? (constraints.maxWidth - 16) / 3
                : (constraints.maxWidth >= 210
                    ? (constraints.maxWidth - 8) / 2
                    : constraints.maxWidth);
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HrvStatTile(
                  width: colWidth,
                  label: s.medianRrLabel,
                  value: viewModel.medianRrMs == null
                      ? '—'
                      : '${viewModel.medianRrMs!.round()} ms',
                  accent: pal.cyan,
                ),
                _HrvStatTile(
                  width: colWidth,
                  label: s.rrRangeLabel,
                  value: rangeText,
                  accent: pal.textPrimary,
                ),
                _HrvStatTile(
                  width: colWidth,
                  label: s.ectopicBurdenLabel,
                  value: '${viewModel.ectopicBurdenPct.toStringAsFixed(1)}%',
                  accent: viewModel.ectopicBurdenPct > 0
                      ? pal.supraS
                      : pal.normalN,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // R-R Tachogram Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.tachogramTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.tapRhythmHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: pal.textMuted),
                ),
                const SizedBox(height: 10),
                _InteractiveChartBox(
                  height: 170,
                  onTap: (localPos, size) {
                    final hit = _RrTachogramPainter.hitTestBeat(
                      points: viewModel.tachogramPoints,
                      durationSeconds: viewModel.durationSeconds,
                      localPos: localPos,
                      size: size,
                    );
                    if (hit != null) {
                      HapticFeedback.selectionClick();
                      onSelectBeat(hit);
                    }
                  },
                  painter: _RrTachogramPainter(
                    points: viewModel.tachogramPoints,
                    durationSeconds: viewModel.durationSeconds,
                    medianRrMs: viewModel.medianRrMs,
                    selectedBeatIndex: selectedBeatIndex,
                    palette: pal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Poincaré Scatter Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.poincareTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                _InteractiveChartBox(
                  height: 220,
                  onTap: (localPos, size) {
                    final hit = _PoincarePainter.hitTestBeat(
                      points: viewModel.poincarePoints,
                      localPos: localPos,
                      size: size,
                    );
                    if (hit != null) {
                      HapticFeedback.selectionClick();
                      onSelectBeat(hit);
                    }
                  },
                  painter: _PoincarePainter(
                    points: viewModel.poincarePoints,
                    selectedBeatIndex: selectedBeatIndex,
                    palette: pal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HrvStatTile extends StatelessWidget {
  const _HrvStatTile({
    required this.width,
    required this.label,
    required this.value,
    required this.accent,
  });

  final double width;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: pal.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: pal.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: tabularStyle(
                theme.textTheme.titleSmall,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveChartBox extends StatelessWidget {
  const _InteractiveChartBox({
    required this.height,
    required this.onTap,
    required this.painter,
  });

  final double height;
  final void Function(Offset localPos, Size size) onTap;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: pal.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => onTap(details.localPosition, size),
              child: CustomPaint(
                size: size,
                painter: painter,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RrTachogramPainter extends CustomPainter {
  _RrTachogramPainter({
    required this.points,
    required this.durationSeconds,
    required this.medianRrMs,
    required this.selectedBeatIndex,
    required this.palette,
  });

  final List<TachogramPoint> points;
  final double durationSeconds;
  final double? medianRrMs;
  final int selectedBeatIndex;
  final BioVantaPalette palette;

  static const _padL = 40.0;
  static const _padR = 12.0;
  static const _padT = 14.0;
  static const _padB = 22.0;

  static (double lo, double hi) _yBounds(List<TachogramPoint> pts) {
    var lo = pts.first.rrMs;
    var hi = pts.first.rrMs;
    for (final p in pts) {
      if (p.rrMs < lo) lo = p.rrMs;
      if (p.rrMs > hi) hi = p.rrMs;
    }
    final pad = math.max((hi - lo) * 0.18, 80.0);
    return (math.max(150.0, lo - pad), hi + pad);
  }

  static Offset _coord(
    TachogramPoint p,
    double dur,
    double loY,
    double hiY,
    Size size,
  ) {
    final w = math.max(size.width - _padL - _padR, 1.0);
    final h = math.max(size.height - _padT - _padB, 1.0);
    final safeDur = math.max(dur, 1.0);
    final x = _padL + (p.timeSeconds / safeDur).clamp(0.0, 1.0) * w;
    final y = _padT + (hiY - p.rrMs) / math.max(hiY - loY, 1.0) * h;
    return Offset(x, y.clamp(_padT, size.height - _padB));
  }

  static int? hitTestBeat({
    required List<TachogramPoint> points,
    required double durationSeconds,
    required Offset localPos,
    required Size size,
  }) {
    if (points.isEmpty) return null;
    final (loY, hiY) = _yBounds(points);
    int? bestBeat;
    var bestDist = 28.0;
    for (final p in points) {
      final pt = _coord(p, durationSeconds, loY, hiY, size);
      final d = (pt - localPos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestBeat = p.beatIndex;
      }
    }
    return bestBeat;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    final (loY, hiY) = _yBounds(points);

    final gridPaint = Paint()
      ..color = palette.gridMinor
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 3; i++) {
      final frac = i / 3.0;
      final val = hiY - frac * (hiY - loY);
      final y = _padT + frac * (size.height - _padT - _padB);
      canvas.drawLine(Offset(_padL, y), Offset(size.width - _padR, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${val.round()}',
          style: TextStyle(
            fontSize: 9.5,
            color: palette.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    // Dashed median R-R reference
    if (medianRrMs != null && medianRrMs! >= loY && medianRrMs! <= hiY) {
      final yMed = _padT +
          (hiY - medianRrMs!) / math.max(hiY - loY, 1.0) * (size.height - _padT - _padB);
      final medPaint = Paint()
        ..color = palette.cyan.withValues(alpha: 0.65)
        ..strokeWidth = 1.2;
      for (var x = _padL; x < size.width - _padR; x += 8) {
        canvas.drawLine(
          Offset(x, yMed),
          Offset(math.min(x + 4, size.width - _padR), yMed),
          medPaint,
        );
      }
    }

    // Connecting line
    final path = Path();
    final coords = [
      for (var i = 0; i < points.length; i++)
        _coord(points[i], durationSeconds, loY, hiY, size),
    ];
    for (var i = 0; i < coords.length; i++) {
      if (i == 0) {
        path.moveTo(coords[i].dx, coords[i].dy);
      } else {
        path.lineTo(coords[i].dx, coords[i].dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.borderAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final c = palette.colorForClass(p.classIndex);
      final pt = coords[i];
      final isSel = p.beatIndex == selectedBeatIndex;
      if (isSel) {
        canvas.drawCircle(
          pt,
          7.0,
          Paint()..color = c.withValues(alpha: 0.25),
        );
      }
      canvas.drawCircle(pt, isSel ? 4.2 : 2.9, Paint()..color = c);
    }

    // Bottom axis bounds
    final endLabel = TextPainter(
      text: TextSpan(
        text: '${durationSeconds.toStringAsFixed(0)} s',
        style: TextStyle(fontSize: 9.5, color: palette.textMuted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    endLabel.paint(
      canvas,
      Offset(size.width - endLabel.width - _padR, size.height - 15),
    );
    final unitLabel = TextPainter(
      text: TextSpan(
        text: 'ms',
        style: TextStyle(fontSize: 9.5, color: palette.textMuted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitLabel.paint(canvas, Offset(6, size.height - 15));
  }

  @override
  bool shouldRepaint(covariant _RrTachogramPainter old) {
    return old.points != points ||
        old.selectedBeatIndex != selectedBeatIndex ||
        old.palette != palette;
  }
}

class _PoincarePainter extends CustomPainter {
  _PoincarePainter({
    required this.points,
    required this.selectedBeatIndex,
    required this.palette,
  });

  final List<PoincarePoint> points;
  final int selectedBeatIndex;
  final BioVantaPalette palette;

  static const _pad = 24.0;

  static (double lo, double hi) _bounds(List<PoincarePoint> pts) {
    var lo = pts.first.rrPrevMs;
    var hi = pts.first.rrPrevMs;
    for (final p in pts) {
      lo = math.min(lo, math.min(p.rrPrevMs, p.rrNextMs));
      hi = math.max(hi, math.max(p.rrPrevMs, p.rrNextMs));
    }
    final margin = math.max((hi - lo) * 0.14, 70.0);
    return (math.max(150.0, lo - margin), hi + margin);
  }

  static Rect _squareArea(Size size) {
    final availW = math.max(size.width - _pad * 2, 1.0);
    final availH = math.max(size.height - _pad * 2, 1.0);
    final side = math.min(availW, availH);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    return Rect.fromLTWH(left, top, side, side);
  }

  static Offset _coord(PoincarePoint p, double lo, double hi, Rect area) {
    final span = math.max(hi - lo, 1.0);
    final x = area.left + (p.rrPrevMs - lo) / span * area.width;
    final y = area.bottom - (p.rrNextMs - lo) / span * area.height;
    return Offset(
      x.clamp(area.left, area.right),
      y.clamp(area.top, area.bottom),
    );
  }

  static int? hitTestBeat({
    required List<PoincarePoint> points,
    required Offset localPos,
    required Size size,
  }) {
    if (points.isEmpty) return null;
    final (lo, hi) = _bounds(points);
    final area = _squareArea(size);
    int? bestBeat;
    var bestDist = 26.0;
    for (final p in points) {
      final pt = _coord(p, lo, hi, area);
      final d = (pt - localPos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestBeat = p.beatIndex;
      }
    }
    return bestBeat;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    final (lo, hi) = _bounds(points);
    final area = _squareArea(size);

    final borderPaint = Paint()
      ..color = palette.gridMajor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(area, borderPaint);

    // Mid grid
    final midX = area.left + area.width / 2;
    final midY = area.top + area.height / 2;
    final gridPaint = Paint()
      ..color = palette.gridMinor
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(midX, area.top), Offset(midX, area.bottom), gridPaint);
    canvas.drawLine(Offset(area.left, midY), Offset(area.right, midY), gridPaint);

    // Identity diagonal y = x (top-right to bottom-left in screen coords)
    final diagPaint = Paint()
      ..color = palette.textMuted.withValues(alpha: 0.45)
      ..strokeWidth = 1.1;
    const steps = 18;
    for (var s = 0; s < steps; s += 2) {
      final t0 = s / steps;
      final t1 = math.min((s + 1) / steps, 1.0);
      canvas.drawLine(
        Offset(area.left + t0 * area.width, area.bottom - t0 * area.height),
        Offset(area.left + t1 * area.width, area.bottom - t1 * area.height),
        diagPaint,
      );
    }

    for (final p in points) {
      final pt = _coord(p, lo, hi, area);
      final c = palette.colorForClass(p.classIndex);
      final isSel = p.beatIndex == selectedBeatIndex;
      if (isSel) {
        canvas.drawCircle(
          pt,
          7.5,
          Paint()..color = c.withValues(alpha: 0.28),
        );
      }
      canvas.drawCircle(
        pt,
        isSel ? 4.4 : 3.1,
        Paint()..color = c.withValues(alpha: isSel ? 1.0 : 0.85),
      );
    }

    final axisStyle = TextStyle(
      fontSize: 9.5,
      color: palette.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final xLabel = TextPainter(
      text: TextSpan(
        text: 'RR[n] (${lo.round()}–${hi.round()} ms)',
        style: axisStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabel.paint(
      canvas,
      Offset(area.left + (area.width - xLabel.width) / 2, area.bottom + 5),
    );

    final yLabel = TextPainter(
      text: TextSpan(text: 'RR[n+1]', style: axisStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    yLabel.paint(canvas, Offset(area.left, math.max(3, area.top - 14)));
  }

  @override
  bool shouldRepaint(covariant _PoincarePainter old) {
    return old.points != points ||
        old.selectedBeatIndex != selectedBeatIndex ||
        old.palette != palette;
  }
}
