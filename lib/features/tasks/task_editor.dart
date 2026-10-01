import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Yeni görev oluşturur veya [task] verilirse düzenler.
Future<void> showTaskEditor(
  BuildContext context, {
  Task? task,
  String? areaId,
  String? goalId,
  DateTime? dueAt,
  bool important = false,
  bool urgent = false,
}) {
  return showAdaptiveSheet<void>(
    context,
    (_) => TaskEditor(
      task: task,
      initialAreaId: areaId,
      initialGoalId: goalId,
      initialDue: dueAt,
      initialImportant: important,
      initialUrgent: urgent,
    ),
  );
}

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({
    super.key,
    this.task,
    this.initialAreaId,
    this.initialGoalId,
    this.initialDue,
    this.initialImportant = false,
    this.initialUrgent = false,
  });

  final Task? task;
  final String? initialAreaId;
  final String? initialGoalId;
  final DateTime? initialDue;
  final bool initialImportant;
  final bool initialUrgent;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _notes = TextEditingController(text: widget.task?.notes ?? '');
  late String? _areaId = widget.task?.areaId ??
      widget.initialAreaId ??
      ref.read(areaFilterProvider) ??
      workAreaId;
  late String? _goalId = widget.task?.goalId ?? widget.initialGoalId;
  late DateTime? _dueDate = widget.task?.dueAt ?? widget.initialDue;
  late TimeOfDay? _dueTime = widget.task != null && widget.task!.dueHasTime
      ? TimeOfDay.fromDateTime(widget.task!.dueAt!)
      : null;
  late int? _estimate = widget.task?.estimateMinutes;
  late int _priority = widget.task?.priority ?? 0;
  late bool _important = widget.task?.important ?? widget.initialImportant;
  late bool _urgent = widget.task?.urgent ?? widget.initialUrgent;
  late String? _recurrence = widget.task?.recurrence;
  bool _saving = false;

  bool get _editing => widget.task != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime? get _dueAt {
    final d = _dueDate;
    if (d == null) return null;
    final t = _dueTime;
    return t == null
        ? DateTime(d.year, d.month, d.day)
        : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(tasksRepoProvider);
    if (_editing) {
      await repo.save(
        widget.task!.id,
        TasksCompanion(
          title: Value(title),
          notes: Value(_notes.text.trim()),
          areaId: Value(_areaId),
          goalId: Value(_goalId),
          dueAt: Value(_dueAt),
          dueHasTime: Value(_dueTime != null && _dueDate != null),
          estimateMinutes: Value(_estimate),
          priority: Value(_priority),
          important: Value(_important),
          urgent: Value(_urgent),
          recurrence: Value(_recurrence),
        ),
      );
    } else {
      await repo.create(
        title: title,
        notes: _notes.text.trim(),
        areaId: _areaId,
        goalId: _goalId,
        dueAt: _dueAt,
        dueHasTime: _dueTime != null && _dueDate != null,
        estimateMinutes: _estimate,
        priority: _priority,
        important: _important,
        urgent: _urgent,
        recurrence: _recurrence,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = (ref.watch(goalsProvider).value ?? const <Goal>[])
        .where((g) => g.status == 'active' || g.id == _goalId)
        .toList();
    final today = startOfDay(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_editing ? 'Görevi düzenle' : 'Yeni görev',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ne yapılacak?'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'Notlar'),
          ),
          const SizedBox(height: 16),
          Text('Alan', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          AreaPicker(value: _areaId, onChanged: (v) => setState(() => _areaId = v)),
          const SizedBox(height: 16),
          Text('Son tarih', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Bugün'),
                selected: _dueDate != null && isSameDay(_dueDate!, today),
                onSelected: (_) => setState(() => _dueDate = today),
              ),
              ChoiceChip(
                label: const Text('Yarın'),
                selected: _dueDate != null &&
                    isSameDay(_dueDate!, addDays(today, 1)),
                onSelected: (_) => setState(() => _dueDate = addDays(today, 1)),
              ),
              ActionChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text(_dueDate == null ||
                        isSameDay(_dueDate!, today) ||
                        isSameDay(_dueDate!, addDays(today, 1))
                    ? 'Tarih seç'
                    : formatRelativeDay(_dueDate!)),
                onPressed: () async {
                  final d = await pickDate(context, _dueDate ?? today);
                  if (d != null) setState(() => _dueDate = d);
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.schedule, size: 18),
                label: Text(_dueTime == null
                    ? 'Saat ekle'
                    : _dueTime!.format(context)),
                onPressed: () async {
                  final t = await pickTime(
                      context, _dueTime ?? const TimeOfDay(hour: 17, minute: 0));
                  if (t != null) {
                    setState(() {
                      _dueTime = t;
                      _dueDate ??= today;
                    });
                  }
                },
              ),
              if (_dueDate != null)
                ActionChip(
                  avatar: const Icon(Icons.close, size: 18),
                  label: const Text('Temizle'),
                  onPressed: () => setState(() {
                    _dueDate = null;
                    _dueTime = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Tahmini süre', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [15, 30, 45, 60, 90, 120, 180])
                ChoiceChip(
                  label: Text(formatDuration(Duration(minutes: m))),
                  selected: _estimate == m,
                  onSelected: (sel) => setState(() => _estimate = sel ? m : null),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Öncelik', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (var p = 0; p < 4; p++)
                ButtonSegment(
                  value: p,
                  label: Text(priorityLabels[p]),
                  icon: p == 0
                      ? null
                      : Icon(Icons.flag, color: priorityColor(p, theme.colorScheme)),
                ),
            ],
            selected: {_priority},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Önemli'),
            subtitle: const Text('Uzun vadeli hedeflerine katkı sağlıyor'),
            value: _important,
            onChanged: (v) => setState(() => _important = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Acil'),
            subtitle: const Text('Hemen ilgilenilmesi gerekiyor'),
            value: _urgent,
            onChanged: (v) => setState(() => _urgent = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _recurrence,
                  decoration: const InputDecoration(labelText: 'Tekrar'),
                  items: [
                    for (final e in recurrenceLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _recurrence = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: goals.any((g) => g.id == _goalId) ? _goalId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Hedef'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Yok')),
                    for (final g in goals)
                      DropdownMenuItem(
                          value: g.id,
                          child: Text(g.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _goalId = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Vazgeç')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_editing ? 'Kaydet' : 'Ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
