import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../ai/plan_day_sheet.dart';
import '../ai/quick_add_sheet.dart';
import '../calendar/block_editor.dart';
import '../calendar/calendar_screen.dart' show blockColor;
import '../focus/focus_controller.dart';
import '../tasks/task_editor.dart';
import '../tasks/task_tile.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  String _greeting(DateTime now) => switch (now.hour) {
        < 6 => 'İyi geceler',
        < 12 => 'Günaydın',
        < 18 => 'İyi günler',
        _ => 'İyi akşamlar',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = startOfDay(now);
    final filter = ref.watch(areaFilterProvider);
    final tasks = ref.watch(filteredOpenTasksProvider).value ?? const <Task>[];
    final overdue = tasks
        .where((t) => t.dueAt != null && startOfDay(t.dueAt!).isBefore(today))
        .toList();
    final dueToday =
        tasks.where((t) => t.dueAt != null && isSameDay(t.dueAt!, today)).toList();
    final doneToday = (ref.watch(completedRecentlyProvider).value ?? const <Task>[])
        .where((t) =>
            t.completedAt != null &&
            isSameDay(t.completedAt!, today) &&
            matchesArea(filter, t.areaId))
        .toList();
    final important = tasks
        .where((t) =>
            t.important &&
            (t.dueAt == null || startOfDay(t.dueAt!).isAfter(today)))
        .take(5)
        .toList();
    final wide = isWide(context);

    final planned = dueToday.length + overdue.length + doneToday.length;
    final progress = planned == 0 ? 0.0 : doneToday.length / planned;

    final left = <Widget>[
      _HeaderCard(
        greeting: _greeting(now),
        date: DateFormat('d MMMM EEEE', 'tr').format(now),
        progress: progress,
        done: doneToday.length,
        total: planned,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => showPlanDay(context, today),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Günümü planla'),
          ),
          OutlinedButton.icon(
            onPressed: () => showQuickAdd(context),
            icon: const Icon(Icons.bolt),
            label: const Text('Hızlı ekle'),
          ),
        ],
      ),
      if (overdue.isNotEmpty) ...[
        SectionHeader('Gecikmiş', count: overdue.length),
        for (final t in overdue) TaskTile(task: t),
      ],
      SectionHeader(
        'Bugün',
        count: dueToday.length,
        trailing: IconButton(
          tooltip: 'Bugüne görev ekle',
          icon: const Icon(Icons.add),
          onPressed: () => showTaskEditor(context, dueAt: today),
        ),
      ),
      if (dueToday.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            doneToday.isEmpty
                ? 'Bugün için tarihli görev yok.'
                : 'Bugünün görevleri bitti. Harika iş! 🎉',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      for (final t in dueToday) TaskTile(task: t),
      if (important.isNotEmpty) ...[
        const SectionHeader('Önemli, sırada bekleyen'),
        for (final t in important) TaskTile(task: t, dense: true),
      ],
      if (doneToday.isNotEmpty) ...[
        SectionHeader('Bugün tamamlanan', count: doneToday.length),
        for (final t in doneToday) TaskTile(task: t, dense: true),
      ],
    ];

    final right = <Widget>[
      _AgendaCard(day: today, now: now),
      const SizedBox(height: 12),
      const _FocusCard(),
      const SizedBox(height: 12),
      _HabitsCard(today: today),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bugün'),
        actions: [
          IconButton(
            tooltip: 'Yeni görev (Ctrl+N)',
            icon: const Icon(Icons.add_task),
            onPressed: () => showTaskEditor(context, dueAt: today),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton(
              tooltip: 'Hızlı ekle',
              onPressed: () => showQuickAdd(context),
              child: const Icon(Icons.auto_awesome),
            ),
      body: Column(
        children: [
          const AreaFilterBar(),
          const SizedBox(height: 8),
          Expanded(
            child: wide
                ? Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 8, 32),
                                children: left),
                          ),
                          Expanded(
                            flex: 2,
                            child: ListView(
                                padding: const EdgeInsets.fromLTRB(8, 0, 16, 32),
                                children: right),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: [
                      ...left.take(2),
                      const SizedBox(height: 12),
                      ...right,
                      ...left.skip(2),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.greeting,
    required this.date,
    required this.progress,
    required this.done,
    required this.total,
  });

  final String greeting;
  final String date;
  final double progress;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting,
                      style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(date,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 8),
                  Text(
                    total == 0
                        ? 'Bugün için planlı görev yok'
                        : '$total görevden $done tanesi tamam',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    backgroundColor:
                        theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
                  ),
                  Center(
                    child: Text('${(progress * 100).round()}%',
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer)),
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

class _AgendaCard extends ConsumerWidget {
  const _AgendaCard({required this.day, required this.now});
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(areaFilterProvider);
    final areas = ref.watch(areaMapProvider);
    final blocks = (ref.watch(blocksInRangeProvider((day, endOfDay(day)))).value ??
            const <TimeBlock>[])
        .where((b) => matchesArea(filter, b.areaId) && b.endAt.isAfter(now))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, size: 20),
                const SizedBox(width: 8),
                Text('Sıradaki', style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Takvime ekle',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => showBlockEditor(context),
                ),
              ],
            ),
            if (blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Bugün için kalan etkinlik yok.',
                    style: theme.textTheme.bodySmall),
              ),
            for (final b in blocks.take(6))
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: blockColor(b, areas, theme.colorScheme),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${formatTime(b.startAt)} – ${formatTime(b.endAt)}'
                    '${b.startAt.isBefore(now) ? ' · şu an' : ''}'),
                onTap: () => showBlockEditor(context, block: b),
              ),
          ],
        ),
      ),
    );
  }
}

class _FocusCard extends ConsumerWidget {
  const _FocusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final focus = ref.watch(focusProvider);
    final entries = ref.watch(entriesInRangeProvider((today, endOfDay(today)))).value ??
        const <TimeEntry>[];
    final total = entries.fold(Duration.zero,
        (s, e) => s + ((e.endAt ?? DateTime.now()).difference(e.startAt)));
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(focus.running ? Icons.timer : Icons.timer_outlined),
        ),
        title: Text('Bugünkü odak: ${formatDuration(total)}'),
        subtitle: Text(focus.running
            ? (focus.mode == FocusMode.pomodoro
                ? '${focus.phase.label} sürüyor'
                : 'Kronometre çalışıyor')
            : '${entries.length} oturum'),
        trailing: IconButton.filledTonal(
          tooltip: focus.running ? 'Duraklat' : 'Başlat',
          icon: Icon(focus.running ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            final ctrl = ref.read(focusProvider.notifier);
            focus.running ? ctrl.pause() : ctrl.start();
          },
        ),
      ),
    );
  }
}

class _HabitsCard extends ConsumerWidget {
  const _HabitsCard({required this.today});
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(areaFilterProvider);
    final habits = (ref.watch(habitsProvider).value ?? const <Habit>[])
        .where((h) => matchesArea(filter, h.areaId) && weekdayInMask(h.weekdays, today))
        .toList();
    final logs =
        ref.watch(habitLogsProvider((addDays(today, -366), today))).value ??
            const <String, int>{};
    if (habits.isEmpty) return const SizedBox.shrink();
    final repo = ref.read(habitsRepoProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.repeat, size: 20),
              const SizedBox(width: 8),
              Text('Bugünün alışkanlıkları', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 4),
            for (final h in habits)
              Builder(builder: (context) {
                final count = logs['${h.id}_${dayKey(today)}'] ?? 0;
                final done = count >= h.targetPerDay;
                final streak = habitStreak(h, logs, today);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  controlAffinity: ListTileControlAffinity.leading,
                  value: done,
                  onChanged: (_) => repo.setCount(
                      h.id, today, done ? 0 : (h.targetPerDay > 1 ? count + 1 : 1)),
                  title: Text('${h.icon.isEmpty ? '' : '${h.icon} '}${h.name}'),
                  subtitle: Text([
                    if (h.targetPerDay > 1) '$count/${h.targetPerDay}',
                    if (streak > 0) '🔥 $streak',
                  ].join(' · ')),
                );
              }),
          ],
        ),
      ),
    );
  }
}
