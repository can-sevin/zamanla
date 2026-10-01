import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../calendar/block_editor.dart';
import 'task_detail_screen.dart';
import 'task_editor.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.dense = false});

  final Task task;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final area = ref.watch(areaMapProvider)[task.areaId];
    final counts = ref.watch(subtaskCountsProvider).value?[task.id];
    final done = task.status == 'done';
    final now = DateTime.now();
    final overdue = !done &&
        task.dueAt != null &&
        (task.dueHasTime
            ? task.dueAt!.isBefore(now)
            : startOfDay(task.dueAt!).isBefore(startOfDay(now)));

    final meta = <Widget>[
      if (task.dueAt != null)
        _Meta(
          icon: Icons.event,
          text: formatDue(task.dueAt!, task.dueHasTime),
          color: overdue ? scheme.error : null,
        ),
      if (area != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          AreaDot(color: Color(area.color)),
          const SizedBox(width: 4),
          Text(area.name, style: theme.textTheme.bodySmall),
        ]),
      if (task.estimateMinutes != null)
        _Meta(
            icon: Icons.timelapse,
            text: formatDuration(Duration(minutes: task.estimateMinutes!))),
      if (counts != null)
        _Meta(icon: Icons.checklist, text: '${counts.$1}/${counts.$2}'),
      if (task.recurrence != null) const _Meta(icon: Icons.repeat, text: ''),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => TaskDetailScreen(taskId: task.id)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: dense ? 2 : 6),
          child: Row(
            children: [
              Checkbox(
                value: done,
                shape: const CircleBorder(),
                onChanged: (v) =>
                    ref.read(tasksRepoProvider).setDone(task, v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? scheme.outline : null,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Wrap(spacing: 10, runSpacing: 2, children: meta),
                    ],
                  ],
                ),
              ),
              if (task.priority > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.flag,
                      size: 18, color: priorityColor(task.priority, scheme)),
                ),
              _TaskMenu(task: task),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: color ?? Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style?.color),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(text, style: style),
        ],
      ],
    );
  }
}

class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Diğer',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await showTaskEditor(context, task: task);
          case 'schedule':
            await scheduleTaskBlock(context, ref, task);
          case 'focus':
            ref.read(focusProvider.notifier).selectTask(task.id, task.areaId);
            if (context.mounted) {
              showSnack(context, 'Odak ekranında "${task.title}" seçildi.');
            }
          case 'delete':
            if (await confirmDialog(context, title: 'Görev silinsin mi?')) {
              await ref.read(tasksRepoProvider).delete(task.id);
            }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Düzenle')),
        PopupMenuItem(value: 'schedule', child: Text('Takvime yerleştir')),
        PopupMenuItem(value: 'focus', child: Text('Odaklan')),
        PopupMenuItem(value: 'delete', child: Text('Sil')),
      ],
    );
  }
}
