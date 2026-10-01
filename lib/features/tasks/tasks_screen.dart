import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../ai/quick_add_sheet.dart';
import 'task_detail_screen.dart';
import 'task_editor.dart';
import 'task_tile.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _query = '';
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Görevlerde ara',
                    filled: false,
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                )
              : const Text('Görevler'),
          actions: [
            IconButton(
              tooltip: _searching ? 'Aramayı kapat' : 'Ara',
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                _query = '';
              }),
            ),
            IconButton(
              tooltip: 'Yapay zeka ile hızlı ekle (Ctrl+K)',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => showQuickAdd(context),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Liste'), Tab(text: 'Öncelik matrisi')],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Yeni görev (Ctrl+N)',
          onPressed: () => showTaskEditor(context),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            const SizedBox(height: 12),
            const AreaFilterBar(),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                children: [
                  _TaskList(query: _query),
                  _EisenhowerMatrix(query: _query),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Task> _search(List<Task> tasks, String query) => query.isEmpty
    ? tasks
    : tasks
        .where((t) =>
            t.title.toLowerCase().contains(query) ||
            t.notes.toLowerCase().contains(query))
        .toList();

/// Görevleri tarihe göre gruplar: Gecikmiş, Bugün, Yarın, Bu hafta, Daha sonra, Tarihsiz.
Map<String, List<Task>> groupTasksByDue(List<Task> tasks, DateTime now) {
  final today = startOfDay(now);
  final tomorrow = addDays(today, 1);
  final weekEnd = addDays(startOfWeek(today), 7);
  final groups = <String, List<Task>>{
    'Gecikmiş': [],
    'Bugün': [],
    'Yarın': [],
    'Bu hafta': [],
    'Daha sonra': [],
    'Tarihsiz': [],
  };
  for (final t in tasks) {
    final due = t.dueAt;
    final String key;
    if (due == null) {
      key = 'Tarihsiz';
    } else if (startOfDay(due).isBefore(today)) {
      key = 'Gecikmiş';
    } else if (isSameDay(due, today)) {
      key = 'Bugün';
    } else if (isSameDay(due, tomorrow)) {
      key = 'Yarın';
    } else if (due.isBefore(weekEnd)) {
      key = 'Bu hafta';
    } else {
      key = 'Daha sonra';
    }
    groups[key]!.add(t);
  }
  groups.removeWhere((_, v) => v.isEmpty);
  return groups;
}

class _TaskList extends ConsumerStatefulWidget {
  const _TaskList({required this.query});
  final String query;

  @override
  ConsumerState<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends ConsumerState<_TaskList> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(filteredOpenTasksProvider);
    final filter = ref.watch(areaFilterProvider);
    final completed = (ref.watch(completedRecentlyProvider).value ?? const <Task>[])
        .where((t) => matchesArea(filter, t.areaId))
        .toList();

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (all) {
        final tasks = _search(all, widget.query);
        final groups = groupTasksByDue(tasks, DateTime.now());
        final done = _search(completed, widget.query);
        if (tasks.isEmpty && done.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: widget.query.isEmpty ? 'Hiç açık görev yok' : 'Sonuç yok',
            message: widget.query.isEmpty
                ? 'Yeni bir görev ekle ya da yapay zekaya "yarın 10:00 rapor gönder" gibi yaz.'
                : null,
          );
        }
        return ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final entry in groups.entries) ...[
                SectionHeader(entry.key, count: entry.value.length),
                for (final t in entry.value) TaskTile(task: t),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _showDone = !_showDone),
                  icon: Icon(_showDone ? Icons.expand_less : Icons.expand_more),
                  label: Text('Tamamlananlar (son 30 gün): ${done.length}'),
                ),
                if (_showDone)
                  for (final t in done) TaskTile(task: t, dense: true),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Quadrant {
  const _Quadrant(this.title, this.subtitle, this.important, this.urgent,
      this.icon, this.color);
  final String title;
  final String subtitle;
  final bool important;
  final bool urgent;
  final IconData icon;
  final Color color;
}

const _quadrants = [
  _Quadrant('Hemen yap', 'Önemli ve acil', true, true,
      Icons.local_fire_department, Color(0xFFD9443B)),
  _Quadrant('Planla', 'Önemli, acil değil', true, false, Icons.event_available,
      Color(0xFF3F6FD8)),
  _Quadrant('Devret / hızlı bitir', 'Acil, önemli değil', false, true,
      Icons.forward_to_inbox, Color(0xFFE59A1F)),
  _Quadrant('Bırak', 'Ne acil ne önemli', false, false,
      Icons.delete_sweep_outlined, Color(0xFF607D8B)),
];

class _EisenhowerMatrix extends ConsumerWidget {
  const _EisenhowerMatrix({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        _search(ref.watch(filteredOpenTasksProvider).value ?? const [], query);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final cards = [
      for (final q in _quadrants)
        _QuadrantCard(
          quadrant: q,
          tasks: tasks
              .where((t) => t.important == q.important && t.urgent == q.urgent)
              .toList(),
        ),
    ];
    if (!wide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          for (final c in cards)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: Row(children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 12),
              Expanded(child: cards[1]),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 12),
              Expanded(child: cards[3]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _QuadrantCard extends ConsumerWidget {
  const _QuadrantCard({required this.quadrant, required this.tasks});
  final _Quadrant quadrant;
  final List<Task> tasks;

  bool get _desktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final list = tasks.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Görevleri buraya sürükle',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          )
        : ListView(
            shrinkWrap: !wide,
            physics: wide ? null : const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [for (final t in tasks) _draggable(context, t)],
          );

    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) =>
          d.data.important != quadrant.important ||
          d.data.urgent != quadrant.urgent,
      onAcceptWithDetails: (d) => ref.read(tasksRepoProvider).save(
            d.data.id,
            TasksCompanion(
              important: Value(quadrant.important),
              urgent: Value(quadrant.urgent),
            ),
          ),
      builder: (context, candidates, _) => Card(
        color: candidates.isNotEmpty
            ? quadrant.color.withValues(alpha: 0.18)
            : quadrant.color.withValues(alpha: 0.07),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(quadrant.icon, color: quadrant.color),
              title: Text(quadrant.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('${quadrant.subtitle} · ${tasks.length}'),
              trailing: IconButton(
                tooltip: 'Bu bölüme görev ekle',
                icon: const Icon(Icons.add),
                onPressed: () => showTaskEditor(
                  context,
                  important: quadrant.important,
                  urgent: quadrant.urgent,
                ),
              ),
            ),
            if (wide) Expanded(child: list) else list,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _draggable(BuildContext context, Task task) {
    final tile = _MatrixTaskTile(task: task);
    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(task.title),
      ),
    );
    final faded = Opacity(opacity: 0.4, child: tile);
    return _desktop
        ? Draggable<Task>(
            data: task, feedback: feedback, childWhenDragging: faded, child: tile)
        : LongPressDraggable<Task>(
            data: task, feedback: feedback, childWhenDragging: faded, child: tile);
  }
}

class _MatrixTaskTile extends ConsumerWidget {
  const _MatrixTaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(areaMapProvider)[task.areaId];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(right: 8),
      leading: Checkbox(
        value: false,
        shape: const CircleBorder(),
        onChanged: (_) => ref.read(tasksRepoProvider).setDone(task, true),
      ),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: task.dueAt == null
          ? null
          : Text(formatDue(task.dueAt!, task.dueHasTime)),
      trailing: area == null ? null : AreaDot(color: Color(area.color)),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => TaskDetailScreen(taskId: task.id)),
      ),
    );
  }
}
