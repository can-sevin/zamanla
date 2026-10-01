import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../tasks/task_editor.dart';
import '../tasks/task_tile.dart';

/// 0..1 arası ilerleme.
double goalProgress(Goal g, List<Task> linked) {
  if (g.status == 'done') return 1;
  if (g.progressMode == 'manual') {
    return g.targetValue <= 0
        ? 0
        : (g.currentValue / g.targetValue).clamp(0, 1).toDouble();
  }
  if (linked.isEmpty) return 0;
  return linked.where((t) => t.status == 'done').length / linked.length;
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(areaFilterProvider);
    final goals = (ref.watch(goalsProvider).value ?? const <Goal>[])
        .where((g) => matchesArea(filter, g.areaId) && g.status != 'archived')
        .toList();
    final active = goals.where((g) => g.status == 'active').toList();
    final done = goals.where((g) => g.status == 'done').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Hedefler')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni hedef',
        onPressed: () => showGoalEditor(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          const AreaFilterBar(),
          const SizedBox(height: 8),
          Expanded(
            child: goals.isEmpty
                ? EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'Henüz hedef yok',
                    message:
                        'İşte ve hayatta ulaşmak istediğin şeyleri ekle; görevleri bunlara bağla.',
                    action: FilledButton.tonal(
                      onPressed: () => showGoalEditor(context),
                      child: const Text('Hedef ekle'),
                    ),
                  )
                : ContentWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      children: [
                        for (final g in active) _GoalCard(goal: g),
                        if (done.isNotEmpty) ...[
                          SectionHeader('Tamamlananlar', count: done.length),
                          for (final g in done) _GoalCard(goal: g),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final area = ref.watch(areaMapProvider)[goal.areaId];
    final linked = ref.watch(tasksByGoalProvider(goal.id)).value ?? const <Task>[];
    final progress = goalProgress(goal, linked);
    final color = area == null ? theme.colorScheme.primary : Color(area.color);
    final daysLeft = goal.targetDate == null
        ? null
        : startOfDay(goal.targetDate!)
            .difference(startOfDay(DateTime.now()))
            .inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => GoalDetailScreen(goalId: goal.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (area != null) ...[
                    Text(area.icon.isEmpty ? '' : area.icon),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(goal.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: goal.status == 'done'
                              ? TextDecoration.lineThrough
                              : null,
                        )),
                  ),
                  Text('${(progress * 100).round()}%',
                      style: theme.textTheme.titleMedium?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (goal.progressMode == 'manual')
                    '${_num(goal.currentValue)} / ${_num(goal.targetValue)} ${goal.unit}'.trim()
                  else
                    '${linked.where((t) => t.status == 'done').length}/${linked.length} görev',
                  if (daysLeft != null)
                    daysLeft < 0
                        ? '${-daysLeft} gün gecikti'
                        : daysLeft == 0
                            ? 'Bugün bitiyor'
                            : '$daysLeft gün kaldı',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: daysLeft != null && daysLeft < 0 && goal.status != 'done'
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});
  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goal = (ref.watch(goalsProvider).value ?? const <Goal>[])
        .where((g) => g.id == goalId && !g.deleted)
        .firstOrNull;
    if (goal == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Hedef bulunamadı'),
      );
    }
    final linked = ref.watch(tasksByGoalProvider(goal.id)).value ?? const <Task>[];
    final progress = goalProgress(goal, linked);
    final repo = ref.read(goalsRepoProvider);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGoalEditor(context, goal: goal),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDialog(context, title: 'Hedef silinsin mi?')) {
                await repo.delete(goal.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showTaskEditor(context, goalId: goal.id, areaId: goal.areaId),
        icon: const Icon(Icons.add),
        label: const Text('Görev ekle'),
      ),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          children: [
            Text(goal.title, style: theme.textTheme.headlineSmall),
            if (goal.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(goal.description, style: theme.textTheme.bodyLarge),
            ],
            if (goal.targetDate != null) ...[
              const SizedBox(height: 8),
              Text('Hedef tarihi: ${formatRelativeDay(goal.targetDate!)}',
                  style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 12),
            ),
            const SizedBox(height: 8),
            Text('${(progress * 100).round()}% tamamlandı',
                style: theme.textTheme.titleSmall),
            if (goal.progressMode == 'manual') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => repo.save(
                        goal.id,
                        GoalsCompanion(
                            currentValue: Value(
                                (goal.currentValue - 1).clamp(0, double.infinity)))),
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Text(
                      '${_num(goal.currentValue)} / ${_num(goal.targetValue)} ${goal.unit}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => repo.save(goal.id,
                        GoalsCompanion(currentValue: Value(goal.currentValue + 1))),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: goal.status == 'done'
                  ? OutlinedButton.icon(
                      onPressed: () => repo.save(
                          goal.id, const GoalsCompanion(status: Value('active'))),
                      icon: const Icon(Icons.undo),
                      label: const Text('Yeniden etkinleştir'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () => repo.save(
                          goal.id, const GoalsCompanion(status: Value('done'))),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('Hedefe ulaştım'),
                    ),
            ),
            SectionHeader('Bağlı görevler', count: linked.length),
            if (linked.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Bu hedefe katkı sağlayan görevleri ekle.'),
              ),
            for (final t in linked) TaskTile(task: t),
          ],
        ),
      ),
    );
  }
}

Future<void> showGoalEditor(BuildContext context, {Goal? goal}) =>
    showAdaptiveSheet<void>(context, (_) => _GoalEditor(goal: goal));

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor({this.goal});
  final Goal? goal;

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _desc = TextEditingController(text: widget.goal?.description ?? '');
  late final _target = TextEditingController(
      text: widget.goal == null ? '10' : _num(widget.goal!.targetValue));
  late final _unit = TextEditingController(text: widget.goal?.unit ?? '');
  late String? _areaId =
      widget.goal?.areaId ?? ref.read(areaFilterProvider) ?? workAreaId;
  late DateTime? _date = widget.goal?.targetDate;
  late String _mode = widget.goal?.progressMode ?? 'tasks';

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final target =
        double.tryParse(_target.text.replaceAll(',', '.').trim()) ?? 100;
    final repo = ref.read(goalsRepoProvider);
    if (widget.goal == null) {
      await repo.create(
        title: title,
        description: _desc.text.trim(),
        areaId: _areaId,
        targetDate: _date,
        progressMode: _mode,
        targetValue: target,
        unit: _unit.text.trim(),
      );
    } else {
      await repo.save(
        widget.goal!.id,
        GoalsCompanion(
          title: Value(title),
          description: Value(_desc.text.trim()),
          areaId: Value(_areaId),
          targetDate: Value(_date),
          progressMode: Value(_mode),
          targetValue: Value(target),
          unit: Value(_unit.text.trim()),
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
          Text(widget.goal == null ? 'Yeni hedef' : 'Hedefi düzenle',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: widget.goal == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Hedef (ör. Yıl sonuna kadar 12 kitap)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Neden önemli? (isteğe bağlı)'),
          ),
          const SizedBox(height: 16),
          Text('Alan', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          AreaPicker(value: _areaId, onChanged: (v) => setState(() => _areaId = v)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_date == null
                ? 'Hedef tarihi seç (isteğe bağlı)'
                : 'Hedef tarihi: ${formatRelativeDay(_date!)}'),
            onPressed: () async {
              final d = await pickDate(
                  context, _date ?? DateTime.now().add(const Duration(days: 30)));
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 16),
          Text('İlerleme nasıl ölçülsün?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'tasks', label: Text('Bağlı görevler')),
              ButtonSegment(value: 'manual', label: Text('Sayısal')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (_mode == 'manual') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Hedef değer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration:
                        const InputDecoration(labelText: 'Birim (kitap, km…)'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Vazgeç')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Kaydet')),
            ],
          ),
        ],
      ),
    );
  }
}
