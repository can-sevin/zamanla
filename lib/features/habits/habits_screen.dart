import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final filter = ref.watch(areaFilterProvider);
    final habits = (ref.watch(habitsProvider).value ?? const <Habit>[])
        .where((h) => matchesArea(filter, h.areaId))
        .toList();
    // Seri hesabı için geriye doğru 1 yıl.
    final logs = ref
            .watch(habitLogsProvider((addDays(today, -366), today)))
            .value ??
        const <String, int>{};
    final days = [for (var i = 6; i >= 0; i--) addDays(today, -i)];

    return Scaffold(
      appBar: AppBar(title: const Text('Alışkanlıklar')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni alışkanlık',
        onPressed: () => showHabitEditor(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          const AreaFilterBar(),
          const SizedBox(height: 8),
          Expanded(
            child: habits.isEmpty
                ? EmptyState(
                    icon: Icons.repeat,
                    title: 'Henüz alışkanlık yok',
                    message:
                        'Su içmek, kitap okumak, spor… Küçük ve düzenli adımlar ekle.',
                    action: FilledButton.tonal(
                      onPressed: () => showHabitEditor(context),
                      child: const Text('Alışkanlık ekle'),
                    ),
                  )
                : ContentWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      children: [
                        for (final h in habits)
                          _HabitCard(
                              habit: h, logs: logs, days: days, today: today),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HabitCard extends ConsumerWidget {
  const _HabitCard({
    required this.habit,
    required this.logs,
    required this.days,
    required this.today,
  });

  final Habit habit;
  final Map<String, int> logs;
  final List<DateTime> days;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = Color(habit.color);
    final streak = habitStreak(habit, logs, today);
    final todayCount = logs['${habit.id}_${dayKey(today)}'] ?? 0;
    final repo = ref.read(habitsRepoProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showHabitEditor(context, habit: habit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Text(habit.icon.isEmpty ? '✓' : habit.icon,
                        style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(habit.name, style: theme.textTheme.titleMedium),
                        Text(
                          [
                            if (streak > 0) '🔥 $streak gün seri',
                            if (habit.targetPerDay > 1)
                              'Bugün $todayCount/${habit.targetPerDay}',
                            if (habit.weekdays != 127)
                              [
                                for (var i = 0; i < 7; i++)
                                  if (habit.weekdays & (1 << i) != 0)
                                    weekdayShort[i],
                              ].join(' '),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (weekdayInMask(habit.weekdays, today))
                    IconButton.filledTonal(
                      tooltip: habit.targetPerDay > 1 ? '+1' : 'Bugün tamamla',
                      isSelected: todayCount >= habit.targetPerDay,
                      selectedIcon: const Icon(Icons.check),
                      icon: Icon(habit.targetPerDay > 1 ? Icons.add : Icons.check),
                      onPressed: () => repo.setCount(
                        habit.id,
                        today,
                        todayCount >= habit.targetPerDay ? 0 : todayCount + 1,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final d in days)
                    _DayDot(
                      label: weekdayShort[d.weekday - 1],
                      count: logs['${habit.id}_${dayKey(d)}'] ?? 0,
                      target: habit.targetPerDay,
                      planned: weekdayInMask(habit.weekdays, d),
                      color: color,
                      isToday: isSameDay(d, today),
                      onTap: () {
                        final c = logs['${habit.id}_${dayKey(d)}'] ?? 0;
                        repo.setCount(
                            habit.id, d, c >= habit.targetPerDay ? 0 : c + 1);
                      },
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

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.count,
    required this.target,
    required this.planned,
    required this.color,
    required this.isToday,
    required this.onTap,
  });

  final String label;
  final int count;
  final int target;
  final bool planned;
  final Color color;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = target == 0 ? 0.0 : (count / target).clamp(0.0, 1.0);
    final done = ratio >= 1;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Column(
        children: [
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isToday ? FontWeight.w800 : null,
                color: isToday ? theme.colorScheme.primary : null,
              )),
          const SizedBox(height: 4),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? color
                  : ratio > 0
                      ? color.withValues(alpha: 0.35)
                      : planned
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.transparent,
              border: planned
                  ? null
                  : Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : count > 0
                    ? Center(
                        child: Text('$count',
                            style: theme.textTheme.labelSmall))
                    : null,
          ),
        ],
      ),
    );
  }
}

Future<void> showHabitEditor(BuildContext context, {Habit? habit}) =>
    showAdaptiveSheet<void>(context, (_) => _HabitEditor(habit: habit));

class _HabitEditor extends ConsumerStatefulWidget {
  const _HabitEditor({this.habit});
  final Habit? habit;

  @override
  ConsumerState<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends ConsumerState<_HabitEditor> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late final _icon = TextEditingController(text: widget.habit?.icon ?? '');
  late int _color = widget.habit?.color ?? paletteColors[1];
  late String? _areaId =
      widget.habit?.areaId ?? ref.read(areaFilterProvider) ?? personalAreaId;
  late int _target = widget.habit?.targetPerDay ?? 1;
  late int _weekdays = widget.habit?.weekdays ?? 127;

  static const _suggestions = ['💧', '📚', '🏃', '🧘', '🥗', '😴', '✍️', '🎯', '💊', '🚭'];

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _weekdays == 0) return;
    final repo = ref.read(habitsRepoProvider);
    if (widget.habit == null) {
      await repo.create(
        name: name,
        icon: _icon.text.trim(),
        color: _color,
        areaId: _areaId,
        targetPerDay: _target,
        weekdays: _weekdays,
      );
    } else {
      await repo.save(
        widget.habit!.id,
        HabitsCompanion(
          name: Value(name),
          icon: Value(_icon.text.trim()),
          color: Value(_color),
          areaId: Value(_areaId),
          targetPerDay: Value(_target),
          weekdays: Value(_weekdays),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.habit == null ? 'Yeni alışkanlık' : 'Alışkanlığı düzenle',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _icon,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22),
                  decoration: const InputDecoration(hintText: '🙂'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: widget.habit == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Alışkanlık adı'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (final s in _suggestions)
                TextButton(
                  onPressed: () => setState(() => _icon.text = s),
                  child: Text(s, style: const TextStyle(fontSize: 20)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Renk', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              for (final c in paletteColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: _color == c
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Alan', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          AreaPicker(value: _areaId, onChanged: (v) => setState(() => _areaId = v)),
          const SizedBox(height: 16),
          Text('Günler', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(weekdayShort[i]),
                  selected: _weekdays & (1 << i) != 0,
                  onSelected: (_) => setState(() => _weekdays ^= 1 << i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Günlük hedef', style: theme.textTheme.labelLarge),
              const Spacer(),
              IconButton(
                onPressed: _target > 1 ? () => setState(() => _target--) : null,
                icon: const Icon(Icons.remove),
              ),
              Text('$_target kez', style: theme.textTheme.titleMedium),
              IconButton(
                onPressed: _target < 20 ? () => setState(() => _target++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.habit != null) ...[
                TextButton(
                  onPressed: () async {
                    await ref.read(habitsRepoProvider).save(widget.habit!.id,
                        const HabitsCompanion(archived: Value(true)));
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Arşivle'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                  onPressed: () async {
                    if (await confirmDialog(context,
                        title: 'Alışkanlık silinsin mi?',
                        message: 'Geçmiş kayıtları da görünmez olacak.')) {
                      await ref.read(habitsRepoProvider).delete(widget.habit!.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Sil'),
                ),
              ],
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Kaydet')),
            ],
          ),
        ],
      ),
    );
  }
}
