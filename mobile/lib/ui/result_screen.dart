import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/analysis_worker.dart';
import 'ecg_plot.dart';
import 'theme.dart';

/// Result: summary cards, scrollable ECG plot, counts and the S/V beat list.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.payload,
    required this.title,
    required this.sourceFs,
  });

  final AnalysisPayload payload;
  final String title;
  final double sourceFs;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _scrollController = ScrollController();
  double _windowSeconds = 8.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll so that [sampleIndex] sits in the middle of the visible window.
  void _jumpToSample(int sampleIndex) {
    if (!_scrollController.hasClients) return;
    final fs = widget.payload.sampleRate.toDouble();
    final viewport = _scrollController.position.viewportDimension;
    final pxPerSecond = viewport / _windowSeconds;
    final target = sampleIndex / fs * pxPerSecond - viewport / 2;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = widget.payload;
    final fs = payload.sampleRate.toDouble();

    final sBeats = <int>[];
    final vBeats = <int>[];
    for (var i = 0; i < payload.pred.length; i++) {
      if (payload.pred[i] == 1) sBeats.add(i);
      if (payload.pred[i] == 2) vBeats.add(i);
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                _SummaryCard(
                  label: 'Beats analyzed',
                  value: '${payload.beatCount}',
                  icon: Icons.favorite_outline,
                ),
                _SummaryCard(
                  label: 'Heart rate',
                  value: payload.heartRate == null
                      ? '—'
                      : '${payload.heartRate!.round()} bpm',
                  icon: Icons.monitor_heart_outlined,
                ),
                _SummaryCard(
                  label: 'S beats',
                  value: '${payload.countOf(1)}',
                  icon: Icons.circle,
                  accent: classSColor,
                ),
                _SummaryCard(
                  label: 'V beats',
                  value: '${payload.countOf(2)}',
                  icon: Icons.circle,
                  accent: classVColor,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('ECG signal', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${_windowSeconds.round()} s window',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: EcgPlot(
                    payload: payload,
                    windowSeconds: _windowSeconds,
                    scrollController: _scrollController,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _windowSeconds,
              min: 3,
              max: 15,
              divisions: 12,
              label: '${_windowSeconds.round()} s',
              onChanged: (v) => setState(() => _windowSeconds = v),
            ),
            const EcgLegend(),
            const SizedBox(height: 20),
            Text('Beat counts', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _CountBarChart(payload: payload),
            const SizedBox(height: 20),
            Text(
              'S and V beats',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              sBeats.isEmpty && vBeats.isEmpty
                  ? 'None detected in this signal.'
                  : 'Tap a row to jump to that beat in the plot.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final i in [...sBeats, ...vBeats])
              _BeatRow(
                index: i,
                timeSeconds: payload.peaks[i] / fs,
                classIndex: payload.pred[i],
                proba: payload.proba[i],
                onTap: () => _jumpToSample(payload.peaks[i]),
              ),
            const SizedBox(height: 24),
            Text(
              'Educational project, not a medical device.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = accent ?? scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal bar chart of the class counts.
class _CountBarChart extends StatelessWidget {
  const _CountBarChart({required this.payload});

  final AnalysisPayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = [payload.countOf(0), payload.countOf(1), payload.countOf(2)];
    final maxCount = math.max(1, counts.reduce(math.max));

    return Column(
      children: [
        for (var c = 0; c < 3; c++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    classLabels[c],
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: colorForClass(c)),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fraction = counts[c] / maxCount;
                      return Stack(
                        children: [
                          Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          Container(
                            height: 22,
                            width: math.max(
                              counts[c] == 0 ? 0 : 6,
                              constraints.maxWidth * fraction,
                            ),
                            decoration: BoxDecoration(
                              color: colorForClass(c),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${counts[c]}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _BeatRow extends StatelessWidget {
  const _BeatRow({
    required this.index,
    required this.timeSeconds,
    required this.classIndex,
    required this.proba,
    required this.onTap,
  });

  final int index;
  final double timeSeconds;
  final int classIndex;
  final List<double> proba;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = colorForClass(classIndex);
    final minutes = timeSeconds ~/ 60;
    final seconds = timeSeconds - minutes * 60;
    final timeText = '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  classLabels[classIndex],
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  timeText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                'p = ${proba[classIndex].toStringAsFixed(2)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
