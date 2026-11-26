import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/analysis_worker.dart';
import '../data/model_bundle.dart';
import '../l10n/strings.dart';
import 'ecg_plot.dart';
import 'theme.dart';

/// Result: summary cards, scrollable ECG plot, counts and the S/V beat list.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.payload,
    required this.sourceFs,
    this.sample,
    this.fileName,
  });

  final AnalysisPayload payload;
  final double sourceFs;

  /// The demo record, when one was analyzed. The title is rebuilt from it on
  /// every frame, so switching the language renames the screen too.
  final SampleRecord? sample;

  /// The imported file name, when a file was analyzed.
  final String? fileName;

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

  double get _durationSeconds {
    final fs = widget.payload.sampleRate.toDouble();
    if (fs <= 0) return 0;
    return widget.payload.signal.length / fs;
  }

  /// Scroll so that [sampleIndex] sits in the middle of the visible window.
  void _jumpToSample(int sampleIndex) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    if (viewport <= 0) return;
    final window = math.min(_windowSeconds, _durationSeconds);
    if (window <= 0) return;
    final fs = widget.payload.sampleRate.toDouble();
    final pxPerSecond = viewport / window;
    final target = sampleIndex / fs * pxPerSecond - viewport / 2;
    _scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  String _title(AppStrings s) {
    final sample = widget.sample;
    if (sample != null) return s.sampleTitle(sample.id, sample.title);
    return widget.fileName ?? s.importedCsvTitle;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = widget.payload;
    final fs = payload.sampleRate.toDouble();

    // Both lists in time order, whatever order the classes came back in.
    final arrhythmia = <int>[
      for (var i = 0; i < payload.pred.length; i++)
        if (payload.pred[i] == 1 || payload.pred[i] == 2) i,
    ]..sort((a, b) => payload.peaks[a].compareTo(payload.peaks[b]));

    final maxWindow = math.max(3.0, math.min(15.0, _durationSeconds));
    final window = math.min(_windowSeconds, maxWindow);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(s), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: s.languageTooltip,
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    s.languageToggle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            onPressed: () {
              final current = appLocaleNotifier.value.languageCode;
              appLocaleNotifier.value =
                  current == 'fa' ? const Locale('en') : const Locale('fa');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(
                children: [
                  _SummaryRow(
                    left: _SummaryCard(
                      label: s.beatsAnalyzed,
                      value: '${payload.beatCount}',
                      icon: Icons.favorite_outline,
                    ),
                    right: _SummaryCard(
                      label: s.heartRate,
                      value: s.bpmValue(payload.heartRate?.round()),
                      icon: Icons.monitor_heart_outlined,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    left: _SummaryCard(
                      label: s.sBeats,
                      value: '${payload.countOf(1)}',
                      icon: Icons.circle,
                      accent: classSColor,
                    ),
                    right: _SummaryCard(
                      label: s.vBeats,
                      value: '${payload.countOf(2)}',
                      icon: Icons.circle,
                      accent: classVColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.ecgSignal,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          s.windowLabel(window.round()),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
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
                          windowSeconds: window,
                          scrollController: _scrollController,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (maxWindow > 3)
                    Slider(
                      value: window,
                      min: 3,
                      max: maxWindow,
                      divisions: math.max(1, (maxWindow - 3).round()),
                      label: s.windowLabel(window.round()),
                      onChanged: (value) =>
                          setState(() => _windowSeconds = value),
                    ),
                  const EcgLegend(),
                  const SizedBox(height: 20),
                  Text(s.beatCounts, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _CountBarChart(payload: payload),
                  const SizedBox(height: 20),
                  Text(s.sAndVBeats, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    arrhythmia.isEmpty
                        ? s.noArrhythmiaDetected
                        : s.tapToJump,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: arrhythmia.length,
                itemBuilder: (context, i) {
                  final index = arrhythmia[i];
                  return _BeatRow(
                    timeSeconds: payload.peaks[index] / fs,
                    classIndex: payload.pred[index],
                    scores: payload.scores[index],
                    onTap: () => _jumpToSample(payload.peaks[index]),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              sliver: SliverToBoxAdapter(
                child: Text(
                  s.disclaimer,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two summary cards side by side, both as tall as the taller one.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
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

/// One S or V beat: time, class and normalized decision score.
class _BeatRow extends StatelessWidget {
  const _BeatRow({
    required this.timeSeconds,
    required this.classIndex,
    required this.scores,
    required this.onTap,
  });

  final double timeSeconds;
  final int classIndex;
  final List<double> scores;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = colorForClass(classIndex);
    // Round to tenths first: 59.98 s must read 1:00.0, never 0:60.0.
    final totalTenths = (timeSeconds * 10).round();
    final minutes = totalTenths ~/ 600;
    final seconds = (totalTenths % 600) / 10.0;
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
                'score = ${scores[classIndex].toStringAsFixed(2)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}