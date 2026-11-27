import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/file_service.dart';
import '../data/model_bundle.dart';
import '../data/signal_parser.dart';
import '../data/signal_units.dart';
import '../l10n/strings.dart';
import 'about_screen.dart';
import 'ecg_view_model.dart';
import 'result_screen.dart';
import 'theme.dart';
import 'widgets/mini_waveform.dart';
import 'widgets/oscilloscope_header.dart';

/// Monitor Tab: live oscilloscope stage, swipeable MIT-BIH rhythm deck,
/// custom CSV/TXT dropzone, signal calibration drawer, and quick session strips.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.embedded = false,
    this.onAnalysisComplete,
    this.recentSessions = const <AnalysisSessionEntry>[],
    this.onOpenSession,
  });

  final bool embedded;
  final ValueChanged<AnalysisSessionEntry>? onAnalysisComplete;
  final List<AnalysisSessionEntry> recentSessions;
  final ValueChanged<AnalysisSessionEntry>? onOpenSession;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _demoRate = '360';
  static const List<String> _deckOrder = <String>['200', '233', '100'];

  final _rateController = TextEditingController(text: _demoRate);
  final _formKey = GlobalKey<FormState>();

  String? _selectedSampleId;
  String? _importedName;
  List<double>? _importedValues;
  int _importedSkipped = 0;

  SignalUnit _unit = SignalUnit.millivolt;
  bool _invert = false;
  bool _calibrationExpanded = true;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  List<SampleRecord> get _orderedSamples {
    final byId = {for (final r in sampleRecords) r.id: r};
    return <SampleRecord>[
      for (final id in _deckOrder)
        if (byId.containsKey(id)) byId[id]!,
      for (final r in sampleRecords)
        if (!_deckOrder.contains(r.id)) r,
    ];
  }

  Color _accentForSample(BioVantaPalette pal, String id) {
    switch (id) {
      case '200':
        return pal.ventricV;
      case '233':
        return pal.supraS;
      case '100':
        return pal.normalN;
      default:
        return pal.cyan;
    }
  }

  Future<void> _pickCsv() async {
    if (_busy) return;
    setState(() => _error = null);
    try {
      final picked = await pickSignalFile();
      if (!mounted || picked == null) return;
      final parsed = await parseSignalTextAsync(picked.text);
      if (!mounted) return;
      if (parsed.values.length < 2) {
        setState(() => _error = AppStrings.of(context).noNumbersInFile);
        return;
      }
      HapticFeedback.selectionClick();
      setState(() {
        _importedName = picked.name;
        _importedValues = parsed.values;
        _importedSkipped = parsed.skippedLines;
        _selectedSampleId = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppStrings.of(context).couldNotReadFile(e));
    }
  }

  String? _validateRate(String? value) {
    final s = AppStrings.of(context);
    final rate = parseSamplingRate(value ?? '');
    if (rate == null) return s.validateRateNumber;
    if (rate < 100 || rate > 2000) return s.validateRateRange;
    return null;
  }

  void _selectSample(SampleRecord sample) {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSampleId = sample.id;
      _importedValues = null;
      _importedName = null;
      _error = null;
      // Bundled MIT-BIH records are strictly 360 Hz.
      _rateController.text = _demoRate;
    });
  }

  Future<void> _quickAnalyzeSample(SampleRecord sample) async {
    if (_busy) return;
    _selectSample(sample);
    await _analyze();
  }

  Future<void> _analyze() async {
    if (_busy) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fs = parseSamplingRate(_rateController.text);
    if (fs == null) return;

    final sample = _selectedSampleId == null
        ? null
        : sampleRecords.firstWhere((r) => r.id == _selectedSampleId);
    if (_importedValues == null && sample == null) {
      setState(() => _error = AppStrings.of(context).pickRecordFirst);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      var values = _importedValues;
      if (values == null) {
        values = await loadSampleValues(sample!);
        if (!mounted) return;
      }
      final raw = values;

      final seconds = raw.length / fs;
      if (seconds < 10) {
        setState(() {
          _busy = false;
          _error = AppStrings.of(context)
              .signalTooShort(seconds.toStringAsFixed(1));
        });
        return;
      }

      var payload = await runAnalysis(
        raw: applySignalUnit(raw, _unit, invert: _invert),
        sourceFs: fs,
      );
      if (!mounted) return;

      final amplitude = payload.p99 - payload.p1;
      final suggestion = suggestUnitFor(amplitude);
      if (suggestion != null && suggestion != _unit) {
        final strings = AppStrings.of(context);
        final chosen = await showDialog<SignalUnit>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(strings.amplitudeWarningTitle),
            content: Text(
              suggestion == SignalUnit.volt
                  ? strings.amplitudeTooSmall(amplitude.toStringAsFixed(3))
                  : strings.amplitudeTooLarge(amplitude.toStringAsFixed(0)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(strings.continueAnyway),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(suggestion),
                child:
                    Text(strings.convertToUnit(strings.unitLabel(suggestion))),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (chosen != null) {
          setState(() => _unit = chosen);
          payload = await runAnalysis(
            raw: applySignalUnit(raw, chosen, invert: _invert),
            sourceFs: fs,
          );
          if (!mounted) return;
        }
      }

      if (payload.beatCount == 0) {
        setState(() {
          _busy = false;
          _error = AppStrings.of(context).noBeatsDetected;
        });
        return;
      }

      final session = AnalysisSessionEntry(
        id: '${sample?.id ?? _importedName ?? 'csv'}-${DateTime.now().microsecondsSinceEpoch}',
        payload: payload,
        sourceFs: fs,
        sample: sample,
        fileName: sample == null ? _importedName : null,
      );

      setState(() => _busy = false);
      if (widget.onAnalysisComplete != null) {
        widget.onAnalysisComplete!(session);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              payload: payload,
              sample: sample,
              fileName: sample == null ? _importedName : null,
              sourceFs: fs,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppStrings.of(context).analysisFailed(e);
      });
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final samples = _orderedSamples;
    final currentRate = parseSamplingRate(_rateController.text) ?? 360.0;

    final body = Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          widget.embedded ? 112 : 28,
        ),
        children: [
          const OscilloscopeHeader(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.appTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pal.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.appTagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: pal.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.embedded) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: s.aboutTooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: pal.surface,
                    foregroundColor: pal.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: pal.border),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline, size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),

          // Demo MIT-BIH Horizontal Swipeable Rhythm Deck
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.demoRecords,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: pal.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.demoDeckHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = math.min(
                222.0,
                math.max(196.0, constraints.maxWidth * 0.68),
              );
              return SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: samples.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final sample = samples[i];
                    return SizedBox(
                      width: cardWidth,
                      child: _RhythmDeckCard(
                        sample: sample,
                        accent: _accentForSample(pal, sample.id),
                        selected: _selectedSampleId == sample.id,
                        busy: _busy,
                        onSelect: () => _selectSample(sample),
                        onQuickAnalyze: () => _quickAnalyzeSample(sample),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 18),

          // Custom Recording Import Dropzone
          Text(
            s.yourOwnSignal,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: pal.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: _importedValues != null
                ? pal.cyan.withValues(alpha: 0.08)
                : pal.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _busy ? null : _pickCsv,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _importedValues != null ? pal.cyan : pal.borderAccent,
                    width: _importedValues != null ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: pal.cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _importedValues != null
                            ? Icons.check_circle_outline
                            : Icons.upload_file_outlined,
                        color: pal.cyan,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _importedName == null
                                ? s.importCsv
                                : s.imported(_importedName!),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _importedValues == null
                                ? s.importSubtitle
                                : '${s.samplesCount(_importedValues!.length, _importedSkipped)} · ${EcgViewModel.formatDurationMmSs(_importedValues!.length / math.max(1.0, currentRate))}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: pal.textMuted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: pal.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Signal Calibration Drawer (expanded by default so rate/unit/polarity stay 1-tap accessible)
          Material(
            color: pal.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: pal.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(
                    () => _calibrationExpanded = !_calibrationExpanded,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Icon(Icons.tune, size: 18, color: pal.cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.calibrationTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${_rateController.text} Hz · ${classUnitShort(_unit)}',
                          style: tabularStyle(
                            theme.textTheme.labelSmall,
                            color: pal.textMuted,
                            monospace: true,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _calibrationExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: pal.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_calibrationExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: s.samplingRateLabel,
                            helperText: s.samplingRateHelper,
                          ),
                          validator: _validateRate,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<SignalUnit>(
                          initialValue: _unit,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: s.signalUnitLabel,
                            helperText: s.signalUnitHelper,
                          ),
                          dropdownColor: pal.surface,
                          items: [
                            for (final unit in SignalUnit.values)
                              DropdownMenuItem<SignalUnit>(
                                value: unit,
                                child: Text(
                                  s.unitLabel(unit),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (unit) {
                                  if (unit != null) setState(() => _unit = unit);
                                },
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.invertPolarity),
                          subtitle: Text(
                            s.invertPolarityHelp,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: pal.textMuted,
                            ),
                          ),
                          value: _invert,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _invert = value),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // In-session Recent Analyses strip
          if (widget.recentSessions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              s.recentAnalyses,
              style: theme.textTheme.labelLarge?.copyWith(
                color: pal.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.recentSessions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final entry = widget.recentSessions[i];
                  final hasAbnormal =
                      entry.payload.countOf(1) + entry.payload.countOf(2) > 0;
                  final badgeColor = hasAbnormal ? pal.supraS : pal.normalN;
                  return ActionChip(
                    avatar: Icon(
                      Icons.history,
                      size: 15,
                      color: badgeColor,
                    ),
                    backgroundColor: pal.surface,
                    side: BorderSide(color: pal.border),
                    label: Text(
                      '${entry.resolveTitle(s)} · ${entry.payload.beatCount}',
                      style: tabularStyle(
                        theme.textTheme.labelMedium,
                        color: pal.textPrimary,
                      ),
                    ),
                    onPressed: widget.onOpenSession == null
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            widget.onOpenSession!(entry);
                          },
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: pal.ventricV.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _analyze,
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.monitor_heart_outlined),
            label: Text(_busy ? s.analyzing : s.analyze),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          const SizedBox(height: 18),
          Container(
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
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(body: SafeArea(child: body));
  }

  static String classUnitShort(SignalUnit unit) {
    switch (unit) {
      case SignalUnit.millivolt:
        return 'mV';
      case SignalUnit.volt:
        return 'V';
      case SignalUnit.microvolt:
        return 'µV';
    }
  }
}

class _RhythmDeckCard extends StatelessWidget {
  const _RhythmDeckCard({
    required this.sample,
    required this.accent,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onQuickAnalyze,
  });

  final SampleRecord sample;
  final Color accent;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onQuickAnalyze;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.08) : pal.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? accent : pal.border,
          width: selected ? 1.6 : 1.0,
        ),
        boxShadow: selected && pal.isDark
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.sampleTitle(sample.id, sample.title),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pal.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.sampleBadge(sample.id),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MiniWaveform(
                recordId: sample.id,
                accentColor: accent,
                height: 44,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.sampleSubtitle(sample.id, sample.subtitle),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: pal.textMuted,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: busy ? null : onQuickAnalyze,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 13, color: accent),
                          const SizedBox(width: 2),
                          Text(
                            s.tapToAnalyze,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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
