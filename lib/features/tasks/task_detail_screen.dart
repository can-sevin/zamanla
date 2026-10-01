import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/ai_service.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../calendar/block_editor.dart';
import '../settings/ai_settings_screen.dart';
import 'task_editor.dart';

final _trackedForTaskProvider =
    StreamProvider.autoDispose.family<Duration, String>((ref, id) => ref
        .watch(timeEntriesRepoProvider)
        .watchByTask(id)
        .map((list) => list.fold(
            Duration.zero,
            (sum, e) =>
                sum + ((e.endAt ?? DateTime.now()).difference(e.startAt)))));

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _subtask = TextEditingController();
  bool _aiBusy = false;

  @override
  void dispose() {
    _subtask.dispose();
    super.dispose();
  }

  Future<void> _addSubtask(Task parent) async {
    final title = _subtask.text.trim();
    if (title.isEmpty) return;
    _subtask.clear();
    await ref.read(tasksRepoProvider).create(
          title: title,
          parentId: parent.id,
          areaId: parent.areaId,
          sortOrder: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
  }

  Future<void> _breakDown(Task task, List<Task> existing) async {
    final ai = await ref.read(aiServiceProvider.future);
    if (!mounted) return;
    if (ai == null) {
      Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()));
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final suggestions = await ai.breakDown(
        title: task.title,
        notes: task.notes,
        existingSubtasks: existing.map((t) => t.title).toList(),
      );
      if (!mounted) return;
      final chosen = await showDialog<List<SubtaskSuggestion>>(
        context: context,
        builder: (_) => _SuggestionDialog(suggestions: suggestions),
      );
      if (chosen == null) return;
      final repo = ref.read(tasksRepoProvider);
      var order = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final s in chosen) {
        await repo.create(
          title: s.title,
          parentId: task.id,
          areaId: task.areaId,
          estimateMinutes: s.estimateMinutes,
          sortOrder: order++,
        );
      }
    } on AiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskAsync = ref.watch(taskProvider(widget.taskId));
    final task = taskAsync.value;
    if (task == null || task.deleted) {
      return Scaffold(
        appBar: AppBar(),
        body: taskAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(icon: Icons.search_off, title: 'Görev bulunamadı'),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtasks = ref.watch(subtasksProvider(task.id)).value ?? const <Task>[];
    final area = ref.watch(areaMapProvider)[task.areaId];
    final goal = (ref.watch(goalsProvider).value ?? const <Goal>[])
        .where((g) => g.id == task.goalId)
        .firstOrNull;
    final tracked = ref.watch(_trackedForTaskProvider(task.id)).value;
    final done = task.status == 'done';

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showTaskEditor(context, task: task),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDialog(context, title: 'Görev silinsin mi?')) {
                await ref.read(tasksRepoProvider).delete(task.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: done,
                  shape: const CircleBorder(),
                  onChanged: (v) =>
                      ref.read(tasksRepoProvider).setDone(task, v ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(task.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            decoration:
                                done ? TextDecoration.lineThrough : null)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (area != null)
                  Chip(
                    avatar: area.icon.isEmpty ? null : Text(area.icon),
                    label: Text(area.name),
                    backgroundColor: Color(area.color).withValues(alpha: 0.15),
                  ),
                if (task.dueAt != null)
                  Chip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(formatDue(task.dueAt!, task.dueHasTime)),
                  ),
                if (task.estimateMinutes != null)
                  Chip(
                    avatar: const Icon(Icons.timelapse, size: 18),
                    label: Text(formatDuration(
                        Duration(minutes: task.estimateMinutes!))),
                  ),
                if (task.priority > 0)
                  Chip(
                    avatar: Icon(Icons.flag,
                        size: 18, color: priorityColor(task.priority, scheme)),
                    label: Text('${priorityLabels[task.priority]} öncelik'),
                  ),
                if (task.important) const Chip(label: Text('Önemli')),
                if (task.urgent) const Chip(label: Text('Acil')),
                if (task.recurrence != null)
                  Chip(
                    avatar: const Icon(Icons.repeat, size: 18),
                    label: Text(recurrenceLabels[task.recurrence] ?? ''),
                  ),
                if (goal != null)
                  Chip(
                    avatar: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(goal.title),
                  ),
                if (tracked != null && tracked > Duration.zero)
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 18),
                    label: Text('${formatDuration(tracked)} çalışıldı'),
                  ),
              ],
            ),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              SelectableText(task.notes, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => scheduleTaskBlock(context, ref, task),
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Takvime yerleştir'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    ref
                        .read(focusProvider.notifier)
                        .selectTask(task.id, task.areaId);
                    showSnack(context,
                        'Odak ekranında bu görev seçildi. Zamanlayıcıyı başlatabilirsin.');
                  },
                  icon: const Icon(Icons.timer),
                  label: const Text('Odaklan'),
                ),
              ],
            ),
            SectionHeader(
              'Alt görevler',
              count: subtasks.isEmpty ? null : subtasks.length,
              trailing: TextButton.icon(
                onPressed: _aiBusy ? null : () => _breakDown(task, subtasks),
                icon: _aiBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Yapay zeka ile parçala'),
              ),
            ),
            for (final s in subtasks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Checkbox(
                  value: s.status == 'done',
                  onChanged: (v) =>
                      ref.read(tasksRepoProvider).setDone(s, v ?? false),
                ),
                title: Text(
                  s.title,
                  style: TextStyle(
                    decoration: s.status == 'done'
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: s.estimateMinutes == null
                    ? null
                    : Text(formatDuration(Duration(minutes: s.estimateMinutes!))),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => ref.read(tasksRepoProvider).delete(s.id),
                ),
              ),
            TextField(
              controller: _subtask,
              decoration: InputDecoration(
                hintText: 'Alt görev ekle',
                prefixIcon: const Icon(Icons.add),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.keyboard_return),
                  onPressed: () => _addSubtask(task),
                ),
              ),
              onSubmitted: (_) => _addSubtask(task),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionDialog extends StatefulWidget {
  const _SuggestionDialog({required this.suggestions});
  final List<SubtaskSuggestion> suggestions;

  @override
  State<_SuggestionDialog> createState() => _SuggestionDialogState();
}

class _SuggestionDialogState extends State<_SuggestionDialog> {
  late final _selected = List<bool>.filled(widget.suggestions.length, true);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Önerilen alt görevler'),
      content: SizedBox(
        width: 480,
        child: widget.suggestions.isEmpty
            ? const Text('Öneri bulunamadı.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < widget.suggestions.length; i++)
                    CheckboxListTile(
                      value: _selected[i],
                      onChanged: (v) => setState(() => _selected[i] = v ?? false),
                      title: Text(widget.suggestions[i].title),
                      subtitle: widget.suggestions[i].estimateMinutes == null
                          ? null
                          : Text(formatDuration(Duration(
                              minutes: widget.suggestions[i].estimateMinutes!))),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(context, [
            for (var i = 0; i < widget.suggestions.length; i++)
              if (_selected[i]) widget.suggestions[i],
          ]),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
