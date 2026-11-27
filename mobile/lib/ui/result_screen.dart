import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/analysis_worker.dart';
import '../data/model_bundle.dart';
import '../l10n/strings.dart';
import 'ecg_plot.dart';
import 'ecg_view_model.dart';
import 'theme.dart';
import 'widgets/beat_xray_painter.dart';
import 'widgets/fullscreen_monitor.dart';
import 'widgets/rhythm_charts.dart';

enum _StudioSubMode { timeline, xray, rhythm }

/// Studio Tab: Clinical Telemetry HUD, live-playback interactive EcgPlot cockpit,
/// Timeline filter stream, Beat X-Ray morphology microscope, and R-R Rhythm charts.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required AnalysisPayload this.payload,
    required this.sourceFs,
    this.sample,
    this.fileName,
    this.embedded = false,
    this.onGoToMonitor,
  });

  const ResultScreen.empty({
    super.key,
    this.embedded = true,
    this.onGoToMonitor,
  })  : payload = null,
        sourceFs = 360.0,
        sample = null,
        fileName = null;

  final AnalysisPayload? payload;
  final double sourceFs;
  final SampleRecord? sample;
  final String? fileName;
  final bool embedded;
  final VoidCallback? onGoToMonitor;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();

  EcgViewModel? _vm;
  double _windowSeconds = 8.0;
  int _selectedBeatIndex = 0;
  TimelineFilter _filter = TimelineFilter.abnormal;
  _StudioSubMode _subMode = _StudioSubMode.timeline;

  bool _playing = false;
  double _playbackSpeed = 1.0;
  double? _playheadSample;
  double _scrollRatio = 0.0;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _rebuildViewModel();
    _ticker = createTicker(_onTick);
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(covariant ResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload ||
        oldWidget.sourceFs != widget.sourceFs) {
      _stopPlayback();
      _playheadSample = null;
      _scrollRatio = 0.0;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      _rebuildViewModel();
    }
  }

  void _rebuildViewModel() {
    final p = widget.payload;
    if (p == null) {
      _vm = null;
      _selectedBeatIndex = 0;
      return;
    }
    final vm = EcgViewModel.fromPayload(p, sourceFs: widget.sourceFs);
    _vm = vm;
    _selectedBeatIndex =
        vm.abnormalBeats.isNotEmpty ? vm.abnormalBeats.first.index : 0;
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final maxExt = _scrollController.position.maxScrollExtent;
    final nextRatio =
        maxExt > 0 ? (_scrollController.offset / maxExt).clamp(0.0, 1.0) : 0.0;
    if ((nextRatio - _scrollRatio).abs() > 0.005) {
      setState(() => _scrollRatio = nextRatio);
    }
  }

  void _onTick(Duration elapsed) {
    final vm = _vm;
    if (!_playing || vm == null || !mounted) return;
    final dt = (_lastTick == Duration.zero)
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;

    final fs = vm.payload.sampleRate.toDouble();
    final total = vm.totalSamples;
    if (fs <= 0 || total <= 0) return;

    final nextSample = (_playheadSample ?? 0.0) + dt * fs * _playbackSpeed;
    if (nextSample >= total) {
      setState(() {
        _playing = false;
        _playheadSample = total - 1;
      });
      _ticker?.stop();
      return;
    }

    final near = vm.nearestBeatIndex(
      nextSample,
      maxDistanceSamples: fs * 0.08,
    );
    setState(() {
      _playheadSample = nextSample;
      if (near != null) _selectedBeatIndex = near;
    });
    _keepPlayheadVisible(nextSample, total);
  }

  void _keepPlayheadVisible(double sample, double totalSamples) {
    if (!_scrollController.hasClients || totalSamples <= 0) return;
    final pos = _scrollController.position;
    final vp = pos.viewportDimension;
    if (vp <= 0) return;
    final contentWidth = vp + pos.maxScrollExtent;
    final x = sample / totalSamples * contentWidth;
    if (x < pos.pixels + vp * 0.12 || x > pos.pixels + vp * 0.85) {
      final target = (x - vp * 0.25).clamp(0.0, pos.maxScrollExtent);
      _scrollController.jumpTo(target);
    }
  }

  void _stopPlayback() {
    _playing = false;
    _ticker?.stop();
  }

  void _togglePlay() {
    final vm = _vm;
    if (vm == null || vm.totalSamples <= 0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _playing = !_playing;
      if (_playing) {
        if (_playheadSample == null || _playheadSample! >= vm.totalSamples - 2) {
          _playheadSample = 0.0;
        }
        _lastTick = Duration.zero;
        _ticker?.start();
      } else {
        _ticker?.stop();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _scrollController
      ..removeListener(_onScrollChanged)
      ..dispose();
    super.dispose();
  }

  void _selectBeatAndJump(int beatIndex, {bool openXRay = false}) {
    final vm = _vm;
    if (vm == null || vm.beats.isEmpty) return;
    final idx = beatIndex.clamp(0, vm.beats.length - 1);
    final beat = vm.beats[idx];
    HapticFeedback.selectionClick();

    setState(() {
      _selectedBeatIndex = idx;
      _playheadSample = beat.peakSample.toDouble();
      if (openXRay) _subMode = _StudioSubMode.xray;
    });
    _jumpPlotToSample(beat.peakSample);
  }

  void _jumpPlotToSample(int sampleIndex) {
    final vm = _vm;
    if (vm == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    if (viewport <= 0) return;
    final window = math.min(_windowSeconds, math.max(3.0, vm.durationSeconds));
    if (window <= 0) return;
    final fs = vm.payload.sampleRate.toDouble();
    if (fs <= 0) return;
    final pxPerSecond = viewport / window;
    final target = (sampleIndex / fs * pxPerSecond - viewport / 2)
        .clamp(0.0, position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _stepAbnormal(int delta) {
    final vm = _vm;
    if (vm == null || vm.abnormalBeats.isEmpty) return;
    final ab = vm.abnormalBeats;
    final chosen = delta > 0
        ? ab.firstWhere(
            (b) => b.index > _selectedBeatIndex,
            orElse: () => ab.first,
          )
        : ab.lastWhere(
            (b) => b.index < _selectedBeatIndex,
            orElse: () => ab.last,
          );
    _selectBeatAndJump(chosen.index);
  }

  String _title(AppStrings s) {
    final sample = widget.sample;
    if (sample != null) return s.sampleTitle(sample.id, sample.title);
    return widget.fileName ?? s.importedCsvTitle;
  }

  Future<void> _copySummary(BuildContext context) async {
    final vm = _vm;
    if (vm == null) return;
    final s = AppStrings.of(context);
    final summary = vm.buildClipboardSummary(s, title: _title(s));
    await Clipboard.setData(ClipboardData(text: summary));
    HapticFeedback.lightImpact();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.summaryCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final vm = _vm;

    if (vm == null) {
      final emptyWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: pal.borderAccent),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monitor_heart_outlined, size: 46, color: pal.cyan),
                const SizedBox(height: 12),
                Text(
                  s.studioEmptyTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: pal.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  s.studioEmptySubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: pal.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.onGoToMonitor != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.onGoToMonitor,
                    icon: const Icon(Icons.sensors),
                    label: Text(s.goToMonitor),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      if (widget.embedded) return emptyWidget;
      return Scaffold(
        appBar: AppBar(title: Text(s.navStudio)),
        body: SafeArea(child: emptyWidget),
      );
    }

    final maxWindow = math.max(3.0, math.min(20.0, vm.durationSeconds));
    final window = math.min(_windowSeconds, maxWindow);
    final activeBeat = vm.beats.isEmpty
        ? null
        : vm.beats[_selectedBeatIndex.clamp(0, vm.beats.length - 1)];
    final listBeats = vm.filteredBeats(_filter);

    final content = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          sliver: SliverList.list(
            children: [
              // Cockpit header bar
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title(s),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pal.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: s.copySummaryTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                    onPressed: () => _copySummary(context),
                  ),
                  IconButton(
                    tooltip: s.fullscreenTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.fullscreen, size: 22),
                    onPressed: () async {
                      _stopPlayback();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullscreenMonitorScreen(
                            viewModel: vm,
                            title: _title(s),
                            initialWindowSeconds: window,
                            initialBeatIndex: _selectedBeatIndex,
                          ),
                        ),
                      );
                    },
                  ),
                  if (!widget.embedded) ...[
                    IconButton(
                      tooltip: s.themeTooltip,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        pal.isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        size: 20,
                      ),
                      onPressed: () {
                        final cur = appThemeModeNotifier.value;
                        appThemeModeNotifier.value = cur == ThemeMode.dark
                            ? ThemeMode.light
                            : ThemeMode.dark;
                      },
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () {
                        final cur = appLocaleNotifier.value.languageCode;
                        appLocaleNotifier.value = cur == 'fa'
                            ? const Locale('en')
                            : const Locale('fa');
                      },
                      child: Text(s.languageToggle),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Clinical Telemetry HUD (zero overflow down to 320 px)
              _TelemetryHudCard(viewModel: vm),
              const SizedBox(height: 14),

              // Interactive EcgPlot Cockpit
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: pal.borderAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.ecgSignal,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (activeBeat != null) ...[
                          Flexible(
                            child: Text(
                              '${EcgViewModel.formatTimestamp(activeBeat.timeSeconds)} · ${classLabels[activeBeat.classIndex]}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tabularStyle(
                                theme.textTheme.labelSmall,
                                color: pal.colorForClass(activeBeat.classIndex),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          s.windowLabel(window.round()),
                          style: tabularStyle(
                            theme.textTheme.labelSmall,
                            color: pal.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 192,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: pal.border),
                          ),
                          child: EcgPlot(
                            payload: vm.payload,
                            windowSeconds: window,
                            scrollController: _scrollController,
                            selectedBeatIndex: _selectedBeatIndex,
                            playheadSample: _playheadSample,
                            onBeatSelected: _selectBeatAndJump,
                          ),
                        ),
                      ),
                    ),
                    if (vm.durationSeconds > window)
                      Slider(
                        value: _scrollRatio.clamp(0.0, 1.0),
                        onChanged: (v) {
                          setState(() => _scrollRatio = v);
                          if (_scrollController.hasClients) {
                            final maxExt =
                                _scrollController.position.maxScrollExtent;
                            _scrollController.jumpTo(v * maxExt);
                          }
                        },
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: _togglePlay,
                          icon: Icon(
                            _playing ? Icons.pause : Icons.play_arrow,
                            size: 16,
                          ),
                          label: Text(_playing ? s.pause : s.play),
                        ),
                        for (final sp in const [0.5, 1.0, 2.0])
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${sp == 1.0 ? '1' : sp}×'),
                            selected: _playbackSpeed == sp,
                            onSelected: (_) =>
                                setState(() => _playbackSpeed = sp),
                          ),
                        for (final w in const [4.0, 8.0, 12.0, 20.0])
                          if (maxWindow >= w || w == 4.0)
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${w.round()}s'),
                              selected: window.round() == w.round(),
                              onSelected: (_) =>
                                  setState(() => _windowSeconds = w),
                            ),
                        if (vm.abnormalBeats.isNotEmpty) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 9),
                            ),
                            onPressed: () => _stepAbnormal(-1),
                            icon: const Icon(Icons.skip_previous, size: 15),
                            label: Text(
                              s.prevAbnormal,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 9),
                            ),
                            onPressed: () => _stepAbnormal(1),
                            icon: const Icon(Icons.skip_next, size: 15),
                            label: Text(
                              s.nextAbnormal,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    const EcgLegend(),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3-Mode Sub-Studio Switcher: Timeline | Beat X-Ray | R-R Rhythm
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: pal.border),
                ),
                child: Row(
                  children: [
                    _SubModePill(
                      label: s.subTabTimeline,
                      icon: Icons.view_list_outlined,
                      selected: _subMode == _StudioSubMode.timeline,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _subMode = _StudioSubMode.timeline);
                      },
                    ),
                    _SubModePill(
                      label: s.subTabXRay,
                      icon: Icons.biotech_outlined,
                      selected: _subMode == _StudioSubMode.xray,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _subMode = _StudioSubMode.xray);
                      },
                    ),
                    _SubModePill(
                      label: s.subTabRhythm,
                      icon: Icons.ssid_chart,
                      selected: _subMode == _StudioSubMode.rhythm,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _subMode = _StudioSubMode.rhythm);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_subMode == _StudioSubMode.timeline) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FilterPill(
                      label: '${s.filterAbnormal} (${vm.abnormalBeats.length})',
                      selected: _filter == TimelineFilter.abnormal,
                      accent: pal.supraS,
                      onTap: () => setState(
                        () => _filter = TimelineFilter.abnormal,
                      ),
                    ),
                    _FilterPill(
                      label: '${s.filterAll} (${vm.beatCount})',
                      selected: _filter == TimelineFilter.all,
                      accent: pal.cyan,
                      onTap: () => setState(() => _filter = TimelineFilter.all),
                    ),
                    _FilterPill(
                      label: 'S (${vm.sCount})',
                      selected: _filter == TimelineFilter.sOnly,
                      accent: pal.supraS,
                      onTap: () =>
                          setState(() => _filter = TimelineFilter.sOnly),
                    ),
                    _FilterPill(
                      label: 'V (${vm.vCount})',
                      selected: _filter == TimelineFilter.vOnly,
                      accent: pal.ventricV,
                      onTap: () =>
                          setState(() => _filter = TimelineFilter.vOnly),
                    ),
                    _FilterPill(
                      label: 'N (${vm.normalCount})',
                      selected: _filter == TimelineFilter.nOnly,
                      accent: pal.normalN,
                      onTap: () =>
                          setState(() => _filter = TimelineFilter.nOnly),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  listBeats.isEmpty ? s.noArrhythmiaDetected : s.tapToJump,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: pal.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (listBeats.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: pal.normalN.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: pal.normalN.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_outlined, color: pal.normalN),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.calmNoArrhythmiaTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: pal.normalN,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else if (_subMode == _StudioSubMode.xray) ...[
                BeatXRayView(
                  viewModel: vm,
                  selectedBeatIndex: _selectedBeatIndex,
                  onSelectBeat: _selectBeatAndJump,
                ),
              ] else ...[
                RhythmAnalyticsView(
                  viewModel: vm,
                  selectedBeatIndex: _selectedBeatIndex,
                  onSelectBeat: _selectBeatAndJump,
                ),
              ],
            ],
          ),
        ),
        if (_subMode == _StudioSubMode.timeline && listBeats.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: listBeats.length,
              itemBuilder: (context, i) {
                final entry = listBeats[i];
                return _BeatRow(
                  entry: entry,
                  selected: entry.index == _selectedBeatIndex,
                  onTap: () => _selectBeatAndJump(entry.index),
                  onInspect: () =>
                      _selectBeatAndJump(entry.index, openXRay: true),
                );
              },
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            widget.embedded ? 112 : 32,
          ),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pal.border),
              ),
              child: Text(
                s.disclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(body: SafeArea(child: content));
  }
}

class _TelemetryHudCard extends StatelessWidget {
  const _TelemetryHudCard({required this.viewModel});

  final EcgViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);

    final total = math.max(1, viewModel.beatCount);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pal.borderAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: pal.normalN,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            s.heartRate,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: pal.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        s.bpmValue(viewModel.bpm),
                        style: tabularStyle(
                          theme.textTheme.headlineMedium,
                          color: pal.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RhythmHealthDonut(
                normalFraction: (viewModel.normalPct / 100.0).clamp(0.0, 1.0),
                label: s.normalRatioLabel,
                palette: pal,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _MiniHudDatum(
                label: s.beatsAnalyzed,
                value: '${viewModel.beatCount}',
              ),
              _MiniHudDatum(
                label: s.durationLabel,
                value: EcgViewModel.formatDurationMmSs(
                  viewModel.durationSeconds,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Proportional N / S / V bar
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (viewModel.normalCount > 0)
                    Expanded(
                      flex: viewModel.normalCount,
                      child: Container(color: pal.normalN),
                    ),
                  if (viewModel.sCount > 0)
                    Expanded(
                      flex: viewModel.sCount,
                      child: Container(color: pal.supraS),
                    ),
                  if (viewModel.vCount > 0)
                    Expanded(
                      flex: viewModel.vCount,
                      child: Container(color: pal.ventricV),
                    ),
                  if (viewModel.beatCount == 0)
                    Expanded(child: Container(color: pal.elevated)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Zero-overflow class count strip down to 320 px
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth >= 252
                  ? (constraints.maxWidth - 16) / 3
                  : (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ClassMetricBox(
                    width: tileWidth,
                    label: s.nBeats,
                    count: viewModel.normalCount,
                    pct: (viewModel.normalCount / total) * 100,
                    color: pal.normalN,
                  ),
                  _ClassMetricBox(
                    width: tileWidth,
                    label: s.sBeats,
                    count: viewModel.sCount,
                    pct: (viewModel.sCount / total) * 100,
                    color: pal.supraS,
                  ),
                  _ClassMetricBox(
                    width: tileWidth,
                    label: s.vBeats,
                    count: viewModel.vCount,
                    pct: (viewModel.vCount / total) * 100,
                    color: pal.ventricV,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniHudDatum extends StatelessWidget {
  const _MiniHudDatum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '$label: ',
            style: theme.textTheme.labelSmall?.copyWith(color: pal.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: tabularStyle(
            theme.textTheme.labelMedium,
            color: pal.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RhythmHealthDonut extends StatelessWidget {
  const _RhythmHealthDonut({
    required this.normalFraction,
    required this.label,
    required this.palette,
  });

  final double normalFraction;
  final String label;
  final BioVantaPalette palette;

  @override
  Widget build(BuildContext context) {
    final pct = (normalFraction * 100).round();
    return SizedBox(
      width: 78,
      height: 78,
      child: CustomPaint(
        painter: _DonutPainter(
          fraction: normalFraction,
          normalColor: palette.normalN,
          ectopicColor: palette.ventricV,
          trackColor: palette.elevated,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$pct%',
                style: tabularStyle(
                  Theme.of(context).textTheme.labelLarge,
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: palette.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.fraction,
    required this.normalColor,
    required this.ectopicColor,
    required this.trackColor,
  });

  final double fraction;
  final Color normalColor;
  final Color ectopicColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const stroke = 6.5;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    const start = -math.pi / 2;
    final normalSweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    final ectopicSweep = 2 * math.pi - normalSweep;

    if (ectopicSweep > 0.02) {
      canvas.drawArc(
        rect,
        start + normalSweep,
        ectopicSweep,
        false,
        Paint()
          ..color = ectopicColor.withValues(alpha: 0.78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }

    if (normalSweep > 0.02) {
      canvas.drawArc(
        rect,
        start,
        normalSweep,
        false,
        Paint()
          ..color = normalColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) {
    return old.fraction != fraction ||
        old.normalColor != normalColor ||
        old.ectopicColor != ectopicColor;
  }
}

class _ClassMetricBox extends StatelessWidget {
  const _ClassMetricBox({
    required this.width,
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
  });

  final double width;
  final String label;
  final int count;
  final double pct;
  final Color color;

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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pal.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: pal.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '$count (${pct.toStringAsFixed(0)}%)',
                style: tabularStyle(
                  theme.textTheme.titleSmall,
                  color: pal.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubModePill extends StatelessWidget {
  const _SubModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? pal.cyan.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: pal.cyan.withValues(alpha: 0.45))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? pal.cyan : pal.textMuted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? pal.cyan : pal.textMuted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      selectedColor: accent.withValues(alpha: 0.18),
      backgroundColor: pal.surface,
      side: BorderSide(
        color: selected ? accent : pal.border,
      ),
      label: Text(
        label,
        style: tabularStyle(
          Theme.of(context).textTheme.labelSmall,
          color: selected ? accent : pal.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _BeatRow extends StatelessWidget {
  const _BeatRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onInspect,
  });

  final EcgBeatEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final color = pal.colorForClass(entry.classIndex);
    final timeText = EcgViewModel.formatTimestamp(entry.timeSeconds);

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      color: selected ? color.withValues(alpha: 0.08) : pal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color : pal.border,
          width: selected ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  classLabels[entry.classIndex],
                  style: tabularStyle(
                    theme.textTheme.labelLarge,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  timeText,
                  style: tabularStyle(
                    theme.textTheme.bodyMedium,
                    color: pal.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'score = ${entry.activeScore.toStringAsFixed(2)}',
                style: tabularStyle(
                  theme.textTheme.bodySmall,
                  color: pal.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: s.inspectBeat,
                icon: Icon(Icons.biotech_outlined, size: 18, color: pal.cyan),
                onPressed: onInspect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
