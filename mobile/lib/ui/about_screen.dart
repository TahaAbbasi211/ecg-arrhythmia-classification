import 'package:flutter/material.dart';

/// About screen: dataset, results and honest limitations.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('ECG Beat Classifier', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Single-lead heartbeat classification, fully on-device.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Data',
              children: const [
                Text(
                  'MIT-BIH Arrhythmia Database (PhysioNet): 48 half-hour '
                  'two-lead recordings at 360 Hz with expert beat annotations. '
                  'Only the first lead (MLII) is used.',
                ),
                SizedBox(height: 8),
                Text(
                  'Inter-patient split: 22 patients for training and 22 '
                  'different patients for testing, so no patient appears in '
                  'both sets.',
                ),
              ],
            ),
            _Section(
              title: 'Test results',
              subtitle: '22 unseen test patients',
              children: const [
                _MetricRow(label: 'N F1', value: '0.965'),
                _MetricRow(label: 'V F1', value: '0.926'),
                _MetricRow(label: 'S F1', value: '0.180'),
                _MetricRow(label: 'Macro F1 (N, S, V)', value: '0.69'),
              ],
            ),
            _Section(
              title: 'Limitations',
              children: const [
                _Bullet('S beats are weak: they look very similar to normal '
                    'beats and differ mostly in timing.'),
                _Bullet('Fusion (F) beats are not predicted at all.'),
                _Bullet('Single lead only, and only one database. '
                    'Not validated on other devices or populations.'),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: scheme.onErrorContainer, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Educational project, not a medical device.',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: theme.textTheme.bodyMedium),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
