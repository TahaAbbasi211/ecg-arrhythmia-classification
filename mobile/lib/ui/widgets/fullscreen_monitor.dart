import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../ecg_plot.dart';
import '../ecg_view_model.dart';
import '../theme.dart';

/// Distraction-free fullscreen ECG monitor supporting zoom, live sweep playback,
/// beat tapping, and S/V beat stepping.
class FullscreenMonitorScreen extends StatefulWidget {
  const FullscreenMonitorScreen({
    super.key,
    required this.viewModel,
    required this.title,
    this.initialWindowSeconds = 8.0,
    this.initialBeatIndex = 0,
  });

  final EcgViewModel viewModel;
  final String title;
  final double initialWindowSeconds;
  final int initialBeatIndex;

  @override
  State<FullscreenMonitorScreen> createState() =>
      _FullscreenMonitorScreenState();
}

class _FullscreenMonitorScreenState extends State<FullscreenMonitorScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late double _windowSeconds;
  late int _selectedBeatIndex;
  bool _playing = false;
  double _speed = 1.0;
  double? _playheadSample;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _windowSeconds = widget.initialWindowSeconds;
    _selectedBeatIndex = widget.viewModel.beats.isEmpty
        ? 0
        : widget.initialBeatIndex.clamp(0, widget.viewModel.beats.length - 1);
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final dt = (_lastTick == Duration.zero)
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;

    final fs = widget.viewModel.payload.sampleRate.toDouble();
    final totalSamples = widget.viewModel.payload.signal.length.toDouble();
    if (fs <= 0 || totalSamples <= 0) return;

    final nextSample =
        (_playheadSample ?? 0.0) + dt * fs * _speed;
    if (nextSample >= totalSamples) {
      setState(() {
        _playing = false;
        _playheadSample = totalSamples - 1;
      });
      _ticker?.stop();
      return;
    }

    final near = widget.viewModel.nearestBeatIndex(
      nextSample,
      maxDistanceSamples: fs * 0.08,
    );
    setState(() {
      _playheadSample = nextSample;
      if (near != null) _selectedBeatIndex = near;
    });
    _keepPlayheadVisible(nextSample);
  }

  void _keepPlayheadVisible(double sample) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final vp = pos.viewportDimension;
    final totalSamples = widget.viewModel.payload.signal.length.toDouble();
    if (vp <= 0 || totalSamples <= 0) return;
    final contentWidth = vp + pos.maxScrollExtent;
    final x = sample / totalSamples * contentWidth;
    if (x < pos.pixels + vp * 0.12 || x > pos.pixels + vp * 0.86) {
      final target = (x - vp * 0.25).clamp(0.0, pos.maxScrollExtent);
      _scrollController.jumpTo(target);
    }
  }

  void _togglePlay() {
    HapticFeedback.lightImpact();
    setState(() {
      _playing = !_playing;
      if (_playing) {
        final total = widget.viewModel.payload.signal.length.toDouble();
        if (_playheadSample == null || _playheadSample! >= total - 2) {
          _playheadSample = 0.0;
        }
        _lastTick = Duration.zero;
        _ticker?.start();
      } else {
        _ticker?.stop();
      }
    });
  }

  void _jumpToBeat(int beatIdx) {
    if (viewModelEmpty) return;
    final beat = widget.viewModel.beats[beatIdx];
    HapticFeedback.selectionClick();
    setState(() {
      _selectedBeatIndex = beatIdx;
      _playheadSample = beat.peakSample.toDouble();
    });
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final vp = pos.viewportDimension;
    final fs = widget.viewModel.payload.sampleRate.toDouble();
    final dur = widget.viewModel.durationSeconds;
    final win = math.min(_windowSeconds, math.max(3.0, dur));
    if (vp > 0 && fs > 0 && win > 0) {
      final pxPerSec = vp / win;
      final target = (beat.peakSample / fs * pxPerSec - vp / 2)
          .clamp(0.0, pos.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  void _stepAbnormal(int delta) {
    final ab = widget.viewModel.abnormalBeats;
    if (ab.isEmpty) return;
    var chosen = ab.first;
    if (delta > 0) {
      chosen = ab.firstWhere(
        (b) => b.index > _selectedBeatIndex,
        orElse: () => ab.first,
      );
    } else {
      chosen = ab.lastWhere(
        (b) => b.index < _selectedBeatIndex,
        orElse: () => ab.last,
      );
    }
    _jumpToBeat(chosen.index);
  }

  bool get viewModelEmpty => widget.viewModel.beats.isEmpty;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final vm = widget.viewModel;
    final dur = math.max(vm.durationSeconds, 1.0);
    final window = math.min(_windowSeconds, math.max(3.0, dur));

    final beat = viewModelEmpty ? null : vm.beats[_selectedBeatIndex];
    final beatColor =
        beat == null ? pal.cyan : pal.colorForClass(beat.classIndex);

    return Scaffold(
      backgroundColor: pal.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: pal.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (beat != null)
                          Text(
                            '${s.beatNumberTime(beat.index + 1, EcgViewModel.formatTimestamp(beat.timeSeconds))} · ${classLabels[beat.classIndex]} (${beat.activeScore.toStringAsFixed(2)})',
                            style: tabularStyle(
                              theme.textTheme.labelMedium,
                              color: beatColor,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.bpmValue(vm.bpm),
                    style: tabularStyle(
                      theme.textTheme.titleSmall,
                      color: pal.normalN,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: s.exitFullscreenTooltip,
                    icon: const Icon(Icons.fullscreen_exit),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: pal.borderAccent),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: EcgPlot(
                      payload: vm.payload,
                      windowSeconds: window,
                      scrollController: _scrollController,
                      selectedBeatIndex: _selectedBeatIndex,
                      playheadSample: _playheadSample,
                      onBeatSelected: _jumpToBeat,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: _togglePlay,
                        icon: Icon(
                          _playing ? Icons.pause : Icons.play_arrow,
                          size: 18,
                        ),
                        label: Text(_playing ? s.pause : s.play),
                      ),
                      const SizedBox(width: 6),
                      for (final sp in const [0.5, 1.0, 2.0])
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text('${sp == 1.0 ? '1' : sp}×'),
                            selected: _speed == sp,
                            onSelected: (_) => setState(() => _speed = sp),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final w in const [4.0, 8.0, 12.0, 20.0])
                        if (dur >= w || w == 4.0)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ChoiceChip(
                              label: Text('${w.round()}s'),
                              selected: _windowSeconds.round() == w.round(),
                              onSelected: (_) =>
                                  setState(() => _windowSeconds = w),
                            ),
                          ),
                      if (vm.abnormalBeats.isNotEmpty) ...[
                        IconButton(
                          tooltip: s.prevAbnormal,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _stepAbnormal(-1),
                          icon: const Icon(Icons.skip_previous),
                        ),
                        IconButton(
                          tooltip: s.nextAbnormal,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _stepAbnormal(1),
                          icon: const Icon(Icons.skip_next),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
