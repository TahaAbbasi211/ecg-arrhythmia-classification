import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'theme.dart';

/// Lab & Info Tab: BioVanta V4.0 identity, Appearance & Language pickers,
/// 3-Stage On-Device Pipeline diagram, DS2 & SVDB benchmarks, and clinical limits.
class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final body = ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        embedded ? 112 : 32,
      ),
      children: [
        // Hero Identity Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pal.borderAccent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.aboutHeadline,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pal.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: pal.cyan.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: pal.cyan.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      s.appVersion,
                      style: tabularStyle(
                        theme.textTheme.labelMedium,
                        color: pal.cyan,
                        fontWeight: FontWeight.w800,
                        monospace: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.aboutTagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Interactive Preferences: Theme & Language
        ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeModeNotifier,
          builder: (context, mode, _) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.themeLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: pal.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.dark_mode_outlined, size: 15),
                        label: Text(s.themeDark),
                        selected: mode == ThemeMode.dark,
                        onSelected: (_) =>
                            appThemeModeNotifier.value = ThemeMode.dark,
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.light_mode_outlined, size: 15),
                        label: Text(s.themeLight),
                        selected: mode == ThemeMode.light,
                        onSelected: (_) =>
                            appThemeModeNotifier.value = ThemeMode.light,
                      ),
                      ChoiceChip(
                        avatar: const Icon(
                          Icons.settings_brightness_outlined,
                          size: 15,
                        ),
                        label: Text(s.themeSystem),
                        selected: mode == ThemeMode.system,
                        onSelected: (_) =>
                            appThemeModeNotifier.value = ThemeMode.system,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: pal.border),
                  const SizedBox(height: 12),
                  Text(
                    s.languageSectionLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: pal.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('English'),
                        selected: !s.isFa,
                        onSelected: (_) =>
                            appLocaleNotifier.value = const Locale('en'),
                      ),
                      ChoiceChip(
                        label: const Text('فارسی'),
                        selected: s.isFa,
                        onSelected: (_) =>
                            appLocaleNotifier.value = const Locale('fa'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),

        // 3-Stage On-Device Pipeline Diagram
        _Section(
          title: s.pipelineTitle,
          children: [
            _PipelineStageCard(
              step: '01',
              title: s.stage1Title,
              subtitle: s.stage1Sub,
              color: pal.cyan,
            ),
            const SizedBox(height: 8),
            _PipelineStageCard(
              step: '02',
              title: s.stage2Title,
              subtitle: s.stage2Sub,
              color: pal.normalN,
            ),
            const SizedBox(height: 8),
            _PipelineStageCard(
              step: '03',
              title: s.stage3Title,
              subtitle: s.stage3Sub,
              color: pal.supraS,
            ),
          ],
        ),

        // Verified Benchmarks: MIT-BIH DS2 + SVDB
        _Section(
          title: s.testResultsTitle,
          subtitle: s.ds2Subtitle,
          children: [
            _MetricBarRow(label: s.labelNF1, value: 0.972, color: pal.normalN),
            _MetricBarRow(label: s.labelVF1, value: 0.952, color: pal.ventricV),
            _MetricBarRow(
              label: '${s.labelSF1} (0.407 excl. 232)',
              valueText: '0.179',
              value: 0.179,
              color: pal.supraS,
            ),
            _MetricBarRow(
              label: s.labelMacroF1,
              value: 0.701,
              color: pal.cyan,
            ),
            _MetricBarRow(
              label: s.labelAccuracy,
              valueText: '94.7%',
              value: 0.947,
              color: pal.textPrimary,
            ),
          ],
        ),
        _Section(
          title: s.svdbSubtitle,
          children: [
            _MetricBarRow(
              label: s.labelMacroF1,
              value: 0.827,
              color: pal.cyan,
            ),
            _MetricBarRow(
              label: s.labelAccuracy,
              valueText: '96.4%',
              value: 0.964,
              color: pal.normalN,
            ),
            const SizedBox(height: 4),
            Text(
              'N F1 = 0.983 · S F1 = 0.762 · V F1 = 0.737',
              style: tabularStyle(
                theme.textTheme.labelMedium,
                color: pal.textMuted,
              ),
            ),
          ],
        ),

        // Datasets & Inter-patient Protocol
        _Section(
          title: s.dataSectionTitle,
          children: [
            Text(s.dataDesc1, style: TextStyle(color: pal.textPrimary)),
            const SizedBox(height: 8),
            Text(s.dataDesc2, style: TextStyle(color: pal.textPrimary)),
          ],
        ),

        // Limitations
        _Section(
          title: s.limitationsTitle,
          children: [
            _Bullet(s.limitationS),
            _Bullet(s.limitationSustainedAtrial),
            _Bullet(s.limitationF),
            _Bullet(s.limitationSingleLead),
          ],
        ),

        // Honest Clinical Warning Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: pal.ventricV.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: scheme.onErrorContainer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.disclaimer,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(s.aboutTitle)),
      body: SafeArea(child: body),
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
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: pal.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PipelineStageCard extends StatelessWidget {
  const _PipelineStageCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String step;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: pal.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              step,
              style: tabularStyle(
                theme.textTheme.labelMedium,
                color: color,
                fontWeight: FontWeight.w800,
                monospace: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: pal.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: pal.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBarRow extends StatelessWidget {
  const _MetricBarRow({
    required this.label,
    required this.value,
    required this.color,
    this.valueText,
  });

  final String label;
  final double value;
  final Color color;
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    final formatted = valueText ?? value.toStringAsFixed(3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: pal.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatted,
                style: tabularStyle(
                  theme.textTheme.titleSmall,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: value.clamp(0.0, 1.0),
              backgroundColor: pal.elevated,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
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
    final pal = BioVantaPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, start: 2, end: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: pal.cyan,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: TextStyle(color: pal.textPrimary)),
          ),
        ],
      ),
    );
  }
}
