import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync_service.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../ai/assistant_screen.dart';
import '../ai/quick_add_sheet.dart';
import '../calendar/calendar_screen.dart';
import '../focus/focus_screen.dart';
import '../goals/goals_screen.dart';
import '../habits/habits_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../tasks/task_editor.dart';
import '../tasks/tasks_screen.dart';
import '../today/today_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
}

final _destinations = <_Destination>[
  _Destination(
    'Bugün',
    Icons.wb_sunny_outlined,
    Icons.wb_sunny,
    (_) => const TodayScreen(),
  ),
  _Destination(
    'Görevler',
    Icons.check_circle_outline,
    Icons.check_circle,
    (_) => const TasksScreen(),
  ),
  _Destination(
    'Takvim',
    Icons.calendar_month_outlined,
    Icons.calendar_month,
    (_) => const CalendarScreen(),
  ),
  _Destination(
    'Odak',
    Icons.timer_outlined,
    Icons.timer,
    (_) => const FocusScreen(),
  ),
  _Destination(
    'Alışkanlıklar',
    Icons.repeat_outlined,
    Icons.repeat,
    (_) => const HabitsScreen(),
  ),
  _Destination(
    'Hedefler',
    Icons.flag_outlined,
    Icons.flag,
    (_) => const GoalsScreen(),
  ),
  _Destination(
    'İstatistik',
    Icons.insights_outlined,
    Icons.insights,
    (_) => const StatsScreen(),
  ),
  _Destination(
    'Asistan',
    Icons.auto_awesome_outlined,
    Icons.auto_awesome,
    (_) => const AssistantScreen(),
  ),
  _Destination(
    'Ayarlar',
    Icons.settings_outlined,
    Icons.settings,
    (_) => const SettingsScreen(),
  ),
];

/// Telefonda alt çubuktaki sekme sayısı; kalanlar "Daha" altında.
const _mobilePrimary = 4;

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _NewTaskIntent extends Intent {
  const _NewTaskIntent();
}

class _QuickAddIntent extends Intent {
  const _QuickAddIntent();
}

class _GoToIntent extends Intent {
  const _GoToIntent(this.index);
  final int index;
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  final _visited = <int>{0};

  void _select(int i) => setState(() {
    _index = i;
    _visited.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    // Telefonda "Daha" sekmesi seçiliyken alt çubukta o vurgulanır.
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _destinations.length; i++)
          _visited.contains(i)
              ? _destinations[i].builder(context)
              : const SizedBox.shrink(),
      ],
    );

    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          const _NewTaskIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          const _QuickAddIntent(),
      for (var i = 0; i < 9; i++)
        SingleActivator(LogicalKeyboardKey(0x00000000031 + i), control: true):
            _GoToIntent(i),
    };

    final scaffold = wide
        ? Scaffold(
            body: Row(
              children: [
                _SideRail(index: _index, onSelect: _select),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          )
        : Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index < _mobilePrimary ? _index : _mobilePrimary,
              onDestinationSelected: (i) =>
                  i == _mobilePrimary ? _openMore(context) : _select(i),
              destinations: [
                for (final d in _destinations.take(_mobilePrimary))
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.apps_outlined),
                  selectedIcon: Icon(Icons.apps),
                  label: 'Daha',
                ),
              ],
            ),
          );

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: {
          _NewTaskIntent: CallbackAction<_NewTaskIntent>(
            onInvoke: (_) => showTaskEditor(context),
          ),
          _QuickAddIntent: CallbackAction<_QuickAddIntent>(
            onInvoke: (_) => showQuickAdd(context),
          ),
          _GoToIntent: CallbackAction<_GoToIntent>(
            onInvoke: (intent) => _select(intent.index),
          ),
        },
        child: Focus(autofocus: true, child: scaffold),
      ),
    );
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = _mobilePrimary; i < _destinations.length; i++)
              ListTile(
                leading: Icon(
                  _index == i
                      ? _destinations[i].selectedIcon
                      : _destinations[i].icon,
                ),
                title: Text(_destinations[i].label),
                selected: _index == i,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _select(i);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final extended = MediaQuery.sizeOf(context).width >= 1200;
    return SafeArea(
      right: false,
      child: SizedBox(
        width: extended ? 232 : 88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hourglass_bottom_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  if (extended) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Zamanla',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: extended
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () => showQuickAdd(context),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Hızlı ekle'),
                    )
                  : IconButton.filled(
                      tooltip: 'Hızlı ekle (Ctrl+K)',
                      onPressed: () => showQuickAdd(context),
                      icon: const Icon(Icons.auto_awesome),
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: NavigationRail(
                extended: extended,
                minExtendedWidth: 232,
                backgroundColor: Colors.transparent,
                selectedIndex: index,
                onDestinationSelected: onSelect,
                labelType: extended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            const _SyncIndicator(),
          ],
        ),
      ),
    );
  }
}

class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null || status.phase == SyncPhase.disabled) {
      return const SizedBox(height: 12);
    }
    final (icon, text) = switch (status.phase) {
      SyncPhase.syncing => (Icons.sync, 'Eşitleniyor…'),
      SyncPhase.error => (Icons.sync_problem, 'Eşitleme hatası'),
      SyncPhase.signedOut => (Icons.cloud_off_outlined, 'Giriş yapılmadı'),
      _ => (Icons.cloud_done_outlined, 'Eşitlendi'),
    };
    final color = status.phase == SyncPhase.error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.outline;
    return Tooltip(
      message: status.error ?? text,
      child: InkWell(
        onTap: () => ref.read(syncServiceProvider).syncNow(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
