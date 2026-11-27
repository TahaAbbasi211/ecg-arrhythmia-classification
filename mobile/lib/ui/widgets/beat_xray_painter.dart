import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ecg/constants.dart' as ecg_constants;
import '../../l10n/strings.dart';
import '../ecg_view_model.dart';
import '../theme.dart';

/// 200-sample Beat X-Ray morphology microscope with dashed median template overlay,
/// P / QRS / T clinical phase bands, R-R timing stats, and normalized `score` bars.
class BeatXRayView extends StatelessWidget {
  const BeatXRayView({
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

    if (viewModel.beats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(s.noBeatsDetected, style: TextStyle(color: pal.textMuted)),
        ),
      );
    }

    final idx = selectedBeatIndex.clamp(0, viewModel.beats.length - 1);
    final beat = viewModel.beats[idx];
    final beatColor = pal.colorForClass(beat.classIndex);
    final beatWindow = viewModel.extractBeatWindow(idx);
    final template = viewModel.medianTemplate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header & beat navigation
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: s.prevAbnormal,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: idx > 0
                      ? () {
                          HapticFeedback.selectionClick();
                          onSelectBeat(idx - 1);
                        }
                      : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        s.xRayTitle,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: pal.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            s.beatNumberTime(
                              idx + 1,
                              EcgViewModel.formatTimestamp(beat.timeSeconds),
                            ),
                            style: tabularStyle(
                              theme.textTheme.titleSmall,
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: beatColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: beatColor.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              classLabels[beat.classIndex],
                              style: tabularStyle(
                                theme.textTheme.labelSmall,
                                color: beatColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: s.nextAbnormal,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: idx < viewModel.beats.length - 1
                      ? () {
                          HapticFeedback.selectionClick();
                          onSelectBeat(idx + 1);
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 200-sample Morphology Painter (always LTR)
            Container(
              height: 196,
              decoration: BoxDecoration(
                color: pal.canvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: beatWindow == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          s.partialWindowNote,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: pal.textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  : Directionality(
                      textDirection: TextDirection.ltr,
                      child: CustomPaint(
                        painter: _BeatXRayPainter(
                          beatWindow: beatWindow,
                          medianTemplate: template,
                          beatColor: beatColor,
                          palette: pal,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),

            // Legend row
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _LegendLine(color: beatColor, label: s.selectedBeatLegend),
                if (template != null)
                  _LegendLine(
                    color: pal.textMuted,
                    label: s.medianTemplateLegend,
                    dashed: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // R-R timing tiles (zero-overflow responsive wrap)
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 250;
                final itemWidth = twoCols
                    ? (constraints.maxWidth - 8) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TelemetryTile(
                      width: itemWidth,
                      label: s.timestampLabel,
                      value: EcgViewModel.formatTimestamp(beat.timeSeconds),
                      accent: pal.cyan,
                    ),
                    _TelemetryTile(
                      width: itemWidth,
                      label: s.vsMedianRrLabel,
                      value: beat.rrRatio == null
                          ? '—'
                          : '${(beat.rrRatio! * 100).round()}%',
                      accent: beatColor,
                    ),
                    _TelemetryTile(
                      width: itemWidth,
                      label: s.prevRrLabel,
                      value: beat.prevRrMs == null
                          ? '—'
                          : '${beat.prevRrMs!.round()} ms',
                      accent: pal.textPrimary,
                    ),
                    _TelemetryTile(
                      width: itemWidth,
                      label: s.nextRrLabel,
                      value: beat.nextRrMs == null
                          ? '—'
                          : '${beat.nextRrMs!.round()} ms',
                      accent: pal.textPrimary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Decision-weighted normalized score bars + raw proba
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.modelScoreHeading,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.weightedScoreCol} · ${s.rawProbCol}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: pal.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var c = 0; c < 4; c++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ScoreBarRow(
                  className: classLabels[c],
                  score: c < beat.scores.length ? beat.scores[c] : 0.0,
                  rawProba: c < beat.proba.length ? beat.proba[c] : 0.0,
                  color: pal.colorForClass(c),
                  isPredicted: beat.classIndex == c,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              s.uncalibratedScoreNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatXRayPainter extends CustomPainter {
  _BeatXRayPainter({
    required this.beatWindow,
    required this.medianTemplate,
    required this.beatColor,
    required this.palette,
  });

  final List<double> beatWindow;
  final List<double>? medianTemplate;
  final Color beatColor;
  final BioVantaPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (beatWindow.length < 2 || size.width <= 0 || size.height <= 0) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final n = beatWindow.length;
    double xFor(int idx) => idx / (n - 1) * size.width;

    // Shaded clinical wave regions (P, QRS, T) from ecg/constants.dart
    final bands = [
      (ecg_constants.pStart, ecg_constants.pEnd, 'P', palette.cyan.withValues(alpha: 0.08)),
      (ecg_constants.qrsStart, ecg_constants.qrsEnd, 'QRS', palette.supraS.withValues(alpha: 0.10)),
      (ecg_constants.tStart, ecg_constants.tEnd, 'T', palette.normalN.withValues(alpha: 0.08)),
    ];
    for (final b in bands) {
      final x0 = xFor(b.$1.clamp(0, n - 1));
      final x1 = xFor(b.$2.clamp(0, n - 1));
      canvas.drawRect(
        Rect.fromLTRB(x0, 0, x1, size.height),
        Paint()..color = b.$4,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: b.$3,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: palette.textMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((x0 + x1 - tp.width) / 2, 6));
    }

    // Fine grid lines + R-peak crosshair
    final gridPaint = Paint()
      ..color = palette.gridMinor
      ..strokeWidth = 0.8;
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final rX = xFor(ecg_constants.rPos.clamp(0, n - 1));
    canvas.drawLine(
      Offset(rX, 0),
      Offset(rX, size.height),
      Paint()
        ..color = palette.gridMajor
        ..strokeWidth = 1.1,
    );

    // Compute unified Y range across beat + median template
    var lo = beatWindow[0];
    var hi = beatWindow[0];
    for (final v in beatWindow) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (medianTemplate != null) {
      for (final v in medianTemplate!) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    final span = math.max(hi - lo, 1e-4);
    const padTop = 24.0;
    const padBottom = 20.0;
    final h = math.max(size.height - padTop - padBottom, 1.0);
    double yFor(double v) => padTop + (hi - v) / span * h;

    // Dashed ghost overlay of recording median template
    if (medianTemplate != null && medianTemplate!.length == n) {
      final dashPaint = Paint()
        ..color = palette.textMuted.withValues(alpha: 0.72)
        ..strokeWidth = 1.35
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < n - 1; i += 4) {
        final j = math.min(i + 2, n - 1);
        canvas.drawLine(
          Offset(xFor(i), yFor(medianTemplate![i])),
          Offset(xFor(j), yFor(medianTemplate![j])),
          dashPaint,
        );
      }
    }

    // Selected beat solid trace
    final beatPath = Path();
    for (var i = 0; i < n; i++) {
      final pt = Offset(xFor(i), yFor(beatWindow[i]));
      if (i == 0) {
        beatPath.moveTo(pt.dx, pt.dy);
      } else {
        beatPath.lineTo(pt.dx, pt.dy);
      }
    }

    if (palette.isDark) {
      canvas.drawPath(
        beatPath,
        Paint()
          ..color = beatColor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      beatPath,
      Paint()
        ..color = beatColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      Offset(rX, yFor(beatWindow[ecg_constants.rPos.clamp(0, n - 1)])),
      4.0,
      Paint()..color = beatColor,
    );

    // Axis ms annotations (-250 ms | R 0 ms | +305 ms)
    const axisLabels = [
      (0.0, '-250 ms', TextAlign.left),
      (0.45, 'R · 0 ms', TextAlign.center),
      (1.0, '+305 ms', TextAlign.right),
    ];
    for (final item in axisLabels) {
      final tp = TextPainter(
        text: TextSpan(
          text: item.$2,
          style: TextStyle(
            fontSize: 9.5,
            color: palette.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = item.$3 == TextAlign.left
          ? 6.0
          : (item.$3 == TextAlign.right
              ? size.width - tp.width - 6.0
              : rX - tp.width / 2);
      tp.paint(canvas, Offset(dx, size.height - 14));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BeatXRayPainter old) {
    return old.beatWindow != beatWindow ||
        old.medianTemplate != medianTemplate ||
        old.beatColor != beatColor ||
        old.palette != palette;
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          Row(
            children: [
              Container(width: 6, height: 2, color: color),
              const SizedBox(width: 2),
              Container(width: 6, height: 2, color: color),
            ],
          )
        else
          Container(
            width: 14,
            height: 2.5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: pal.textMuted),
          ),
        ),
      ],
    );
  }
}

class _TelemetryTile extends StatelessWidget {
  const _TelemetryTile({
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: pal.elevated,
          borderRadius: BorderRadius.circular(11),
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
            const SizedBox(height: 2),
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

class _ScoreBarRow extends StatelessWidget {
  const _ScoreBarRow({
    required this.className,
    required this.score,
    required this.rawProba,
    required this.color,
    required this.isPredicted,
  });

  final String className;
  final double score;
  final double rawProba;
  final Color color;
  final bool isPredicted;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final clamped = score.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                className,
                style: tabularStyle(
                  theme.textTheme.labelLarge,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'score = ${score.toStringAsFixed(2)}',
                        style: tabularStyle(
                          theme.textTheme.labelSmall,
                          color: isPredicted ? pal.textPrimary : pal.textMuted,
                          fontWeight: isPredicted
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(p=${rawProba.toStringAsFixed(2)})',
                        style: tabularStyle(
                          theme.textTheme.labelSmall,
                          color: pal.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            children: [
              Container(
                height: 10,
                color: pal.elevated,
              ),
              FractionallySizedBox(
                widthFactor: math.max(clamped, clamped > 0 ? 0.02 : 0.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 10,
                  decoration: BoxDecoration(
                    color: isPredicted ? color : color.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
