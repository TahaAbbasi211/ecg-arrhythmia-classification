import 'package:flutter/material.dart';

import '../data/file_service.dart';
import '../data/model_bundle.dart';
import '../data/signal_parser.dart';
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
  final _rateController = TextEditingController(text: '360');
  final _formKey = GlobalKey<FormState>();

  String? _selectedSampleId;
  String? _importedName;
  List<double>? _importedValues;
  int _importedSkipped = 0;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _pickCsv() async {
    final s = AppStrings.of(context);
    setState(() => _error = null);
    try {
      final result = await pickSignalFile();
      if (result == null) return;
      final parsed = parseSignalText(result.text);
      if (parsed.values.length < 2) {
        setState(() => _error = s.noNumbersInFile);
        return;
      }
      setState(() {
        _importedName = result.name;
        _importedValues = parsed.values;
        _importedSkipped = parsed.skippedLines;
        _selectedSampleId = null;
      });
    } catch (e) {
      setState(() => _error = s.couldNotReadFile(e));
    }
  }

  String? _validateRate(String? value) {
    final s = AppStrings.of(context);
    final v = double.tryParse((value ?? '').trim());
    if (v == null) return s.validateRateNumber;
    if (v < 100 || v > 2000) return s.validateRateRange;
    return null;
  }

  Future<void> _analyze() async {
    final s = AppStrings.of(context);
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fs = double.parse(_rateController.text.trim());
    List<double> raw;
    String title;
    if (_importedValues != null) {
      raw = _importedValues!;
      title = _importedName ?? (s.isFa ? 'فایل CSV بارگذاری‌شده' : 'Imported CSV');
    } else if (_selectedSampleId != null) {
      final sample =
          sampleRecords.firstWhere((s) => s.id == _selectedSampleId);
      raw = await loadSampleValues(sample);
      title = s.sampleTitle(sample.id, sample.title);
    } else {
      setState(() => _error = s.pickRecordFirst);
      return;
    }

    final seconds = raw.length / fs;
    if (seconds < 10) {
      setState(() => _error = s.signalTooShort(seconds.toStringAsFixed(1)));
      return;
    }

    setState(() => _busy = true);
    try {
      final payload = await runAnalysis(raw: raw, sourceFs: fs);
      if (payload.beatCount == 0) {
        setState(() {
          _busy = false;
          _error = s.noBeatsDetected;
        });
        return;
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            payload: payload,
            title: title,
            sourceFs: fs,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = s.analysisFailed(e);
      });
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: s.samplingRateLabel,
                  helperText: s.samplingRateHelper,
                ),
                validator: _validateRate,
                enabled: !_busy,
              ),
              const SizedBox(height: 20),
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
                        Icon(Icons.error_outline,
                            color: scheme.onErrorContainer, size: 20),
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
