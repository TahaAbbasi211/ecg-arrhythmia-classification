import 'package:flutter/material.dart';

import '../data/file_service.dart';
import '../data/model_bundle.dart';
import '../data/signal_parser.dart';
import '../data/signal_units.dart';
import '../l10n/strings.dart';
import 'about_screen.dart';
import 'result_screen.dart';

/// Home: pick a demo record or import a CSV, set the rate, analyze.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _demoRate = '360';

  final _rateController = TextEditingController(text: _demoRate);
  final _formKey = GlobalKey<FormState>();

  String? _selectedSampleId;
  String? _importedName;
  List<double>? _importedValues;
  int _importedSkipped = 0;

  SignalUnit _unit = SignalUnit.millivolt;
  bool _invert = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _pickCsv() async {
    if (_busy) return;
    setState(() => _error = null);
    try {
      final picked = await pickSignalFile();
      if (!mounted || picked == null) return;
      // Parsing runs off the UI thread: a 20 MB file must not drop frames.
      final parsed = await parseSignalTextAsync(picked.text);
      if (!mounted) return;
      if (parsed.values.length < 2) {
        setState(() => _error = AppStrings.of(context).noNumbersInFile);
        return;
      }
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

      // A filtered ECG spans about 0.5-5 mV. A much smaller or much larger
      // spread means the input unit is probably wrong. Offer the conversion,
      // never apply it silently.
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
                child: Text(strings.convertToUnit(strings.unitLabel(suggestion))),
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

      setState(() => _busy = false);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.appTitle),
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
          IconButton(
            tooltip: s.aboutTooltip,
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                s.appTagline,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Text(s.demoRecords, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final sample in sampleRecords)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SampleTile(
                    sample: sample,
                    selected: _selectedSampleId == sample.id,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _selectedSampleId = sample.id;
                              _importedValues = null;
                              _importedName = null;
                              _error = null;
                              // The bundled records are all 360 Hz, so a rate
                              // left over from an imported file would be wrong.
                              _rateController.text = _demoRate;
                            }),
                  ),
                ),
              const SizedBox(height: 12),
              Text(s.yourOwnSignal, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickCsv,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _importedName == null
                      ? s.importCsv
                      : s.imported(_importedName!),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_importedValues != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.samplesCount(_importedValues!.length, _importedSkipped),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _rateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: s.samplingRateLabel,
                  helperText: s.samplingRateHelper,
                ),
                validator: _validateRate,
                enabled: !_busy,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SignalUnit>(
                initialValue: _unit,
                decoration: InputDecoration(
                  labelText: s.signalUnitLabel,
                  helperText: s.signalUnitHelper,
                ),
                items: [
                  for (final unit in SignalUnit.values)
                    DropdownMenuItem<SignalUnit>(
                      value: unit,
                      child: Text(s.unitLabel(unit)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (unit) {
                        if (unit != null) setState(() => _unit = unit);
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.invertPolarity),
                subtitle: Text(s.invertPolarityHelp),
                value: _invert,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _invert = value),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: scheme.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _busy ? null : _analyze,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.monitor_heart_outlined),
                label: Text(_busy ? s.analyzing : s.analyze),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                s.disclaimer,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleTile extends StatelessWidget {
  const _SampleTile({
    required this.sample,
    required this.selected,
    required this.onTap,
  });

  final SampleRecord sample;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.sampleTitle(sample.id, sample.title),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.sampleSubtitle(sample.id, sample.subtitle),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}