import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import 'about_screen.dart';
import 'ecg_view_model.dart';
import 'home_screen.dart';
import 'result_screen.dart';
import 'theme.dart';

/// 3-destination Floating Glass Dock shell wrapping Monitor, Studio, and Lab & Info.
class InstrumentShell extends StatefulWidget {
  const InstrumentShell({super.key});

  @override
  State<InstrumentShell> createState() => _InstrumentShellState();
}

class _InstrumentShellState extends State<InstrumentShell> {
  int _tabIndex = 0;
  AnalysisSessionEntry? _activeSession;
  final List<AnalysisSessionEntry> _recentSessions = [];
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    final inTest = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
    if (inTest) {
      _entered = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _entered = true);
      });
    }
  }

  void _handleAnalysisComplete(AnalysisSessionEntry session) {
    setState(() {
      _activeSession = session;
      _recentSessions.removeWhere(
        (item) =>
            item.sample?.id == session.sample?.id &&
            item.fileName == session.fileName &&
            item.sourceFs == session.sourceFs &&
            item.payload.beatCount == session.payload.beatCount,
      );
      _recentSessions.insert(0, session);
      if (_recentSessions.length > 6) {
        _recentSessions.removeLast();
      }
      _tabIndex = 1;
    });
  }

  void _openSession(AnalysisSessionEntry session) {
    setState(() {
      _activeSession = session;
      _tabIndex = 1;
    });
  }

  void _selectTab(int idx) {
    if (_tabIndex == idx) return;
    HapticFeedback.selectionClick();
    setState(() => _tabIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pal = BioVantaPalette.of(context);
    final active = _activeSession;

    return Scaffold(
      backgroundColor: pal.canvas,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: AnimatedOpacity(
          opacity: _entered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          child: IndexedStack(
            index: _tabIndex,
            children: [
              HomeScreen(
                embedded: true,
                recentSessions: _recentSessions,
                onAnalysisComplete: _handleAnalysisComplete,
                onOpenSession: _openSession,
              ),
              active == null
                  ? ResultScreen.empty(
                      embedded: true,
                      onGoToMonitor: () => _selectTab(0),
                    )
                  : ResultScreen(
                      payload: active.payload,
                      sourceFs: active.sourceFs,
                      sample: active.sample,
                      fileName: active.fileName,
                      embedded: true,
                    ),
              const AboutScreen(embedded: true),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: pal.dockBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: pal.borderAccent),
                boxShadow: pal.isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  _DockItem(
                    label: s.navMonitor,
                    icon: Icons.sensors_outlined,
                    activeIcon: Icons.sensors,
                    selected: _tabIndex == 0,
                    onTap: () => _selectTab(0),
                  ),
                  _DockItem(
                    label: s.navStudio,
                    icon: Icons.monitor_heart_outlined,
                    activeIcon: Icons.monitor_heart,
                    selected: _tabIndex == 1,
                    badgeCount: active?.payload.countOf(1) == null
                        ? null
                        : active!.payload.countOf(1) +
                            active.payload.countOf(2),
                    onTap: () => _selectTab(1),
                  ),
                  _DockItem(
                    label: s.navLabInfo,
                    icon: Icons.biotech_outlined,
                    activeIcon: Icons.biotech,
                    selected: _tabIndex == 2,
                    onTap: () => _selectTab(2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.badgeCount,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final pal = BioVantaPalette.of(context);
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? pal.cyan.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: selected
                ? Border.all(color: pal.cyan.withValues(alpha: 0.35))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 19,
                color: selected ? pal.cyan : pal.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? pal.cyan : pal.textMuted,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeCount != null && badgeCount! > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: pal.supraS.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: tabularStyle(
                      theme.textTheme.labelSmall,
                      color: pal.supraS,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
