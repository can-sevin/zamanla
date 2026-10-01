import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

DateTime roundUpToQuarter(DateTime d) {
  final minutes = d.minute % 15 == 0 && d.second == 0 ? d.minute : (d.minute ~/ 15 + 1) * 15;
  return DateTime(d.year, d.month, d.day, d.hour).add(Duration(minutes: minutes));
}

/// [from] ile [until] arasında [length] uzunluğunda ilk boş aralık.
DateTime? findFreeSlot(
  List<TimeBlock> blocks,
  DateTime from,
  DateTime until,
  Duration length,
) {
  var cursor = roundUpToQuarter(from);
  final sorted = [...blocks]..sort((a, b) => a.startAt.compareTo(b.startAt));
  for (final b in sorted) {
    if (!b.endAt.isAfter(cursor)) continue;
    if (!b.startAt.isBefore(cursor.add(length))) break;
    cursor = roundUpToQuarter(b.endAt);
  }
  return cursor.add(length).isAfter(until) ? null : cursor;
}

/// Görev için uygun bir boşluk bulup blok düzenleyicisini önceden doldurur.
Future<void> scheduleTaskBlock(
    BuildContext context, WidgetRef ref, Task task) async {
  final settings = ref.read(settingsProvider);
  final now = DateTime.now();
  var day = task.dueAt != null && startOfDay(task.dueAt!).isAfter(now)
      ? startOfDay(task.dueAt!)
      : startOfDay(now);
  final length = Duration(minutes: task.estimateMinutes ?? 60);
  DateTime? start;
  for (var i = 0; i < 14 && start == null; i++) {
    final dayStart = day.add(Duration(minutes: settings.workStartMinutes));
    final dayEnd = day.add(Duration(minutes: settings.workEndMinutes));
    final from = dayStart.isAfter(now) ? dayStart : now;
    if (from.isBefore(dayEnd)) {
      final blocks =
          await ref.read(blocksRepoProvider).getRange(day, endOfDay(day));
      start = findFreeSlot(blocks, from, dayEnd, length);
    }
    if (start == null) day = addDays(day, 1);
  }
  start ??= roundUpToQuarter(now);
  if (!context.mounted) return;
  await showBlockEditor(
    context,
    start: start,
    end: start.add(length),
    taskId: task.id,
    title: task.title,
    areaId: task.areaId,
    kind: 'task',
  );
}

Future<void> showBlockEditor(
  BuildContext context, {
  TimeBlock? block,
  DateTime? start,
  DateTime? end,
  String? taskId,
  String? title,
  String? areaId,
  String kind = 'event',
}) {
  return showAdaptiveSheet<void>(
    context,
    (_) => BlockEditor(
      block: block,
      initialStart: start,
      initialEnd: end,
      initialTaskId: taskId,
      initialTitle: title,
      initialAreaId: areaId,
      initialKind: kind,
    ),
  );
}

class BlockEditor extends ConsumerStatefulWidget {
  const BlockEditor({
    super.key,
    this.block,
    this.initialStart,
    this.initialEnd,
    this.initialTaskId,
    this.initialTitle,
    this.initialAreaId,
    this.initialKind = 'event',
  });

  final TimeBlock? block;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String? initialTaskId;
  final String? initialTitle;
  final String? initialAreaId;
  final String initialKind;

  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<BlockEditor> {
  late final _title = TextEditingController(
      text: widget.block?.title ?? widget.initialTitle ?? '');
  late final _notes = TextEditingController(text: widget.block?.notes ?? '');
  late DateTime _start = widget.block?.startAt ??
      widget.initialStart ??
      roundUpToQuarter(DateTime.now());
  late DateTime _end = widget.block?.endAt ??
      widget.initialEnd ??
      _start.add(const Duration(hours: 1));
  late String _kind = widget.block?.kind ?? widget.initialKind;
  late String? _areaId = widget.block?.areaId ??
      widget.initialAreaId ??
      ref.read(areaFilterProvider) ??
      workAreaId;
  late String? _taskId = widget.block?.taskId ?? widget.initialTaskId;

  bool get _editing => widget.block != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var title = _title.text.trim();
    if (title.isEmpty) title = blockKinds[_kind]!;
    if (!_end.isAfter(_start)) {
      showSnack(context, 'Bitiş saati başlangıçtan sonra olmalı.');
      return;
    }
    final repo = ref.read(blocksRepoProvider);
    if (_editing) {
      await repo.save(
        widget.block!.id,
        BlocksCompanion(
          title: Value(title),
          notes: Value(_notes.text.trim()),
          startAt: Value(_start),
          endAt: Value(_end),
          kind: Value(_kind),
          areaId: Value(_areaId),
          taskId: Value(_taskId),
        ),
      );
    } else {
      await repo.create(
        title: title,
        notes: _notes.text.trim(),
        startAt: _start,
        endAt: _end,
        kind: _kind,
        areaId: _areaId,
        taskId: _taskId,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openTasks = ref.watch(openTasksProvider).value ?? const <Task>[];
    final duration = _end.difference(_start);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_editing ? 'Bloğu düzenle' : 'Takvime ekle',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: [
              for (final e in blockKinds.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: !_editing && (widget.initialTitle?.isEmpty ?? true),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Başlık'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(formatRelativeDay(_start)),
                  onPressed: () async {
                    final d = await pickDate(context, _start);
                    if (d == null) return;
                    setState(() {
                      final len = _end.difference(_start);
                      _start = DateTime(
                          d.year, d.month, d.day, _start.hour, _start.minute);
                      _end = _start.add(len);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  child: Text(formatTime(_start)),
                  onPressed: () async {
                    final t = await pickTime(context, TimeOfDay.fromDateTime(_start));
                    if (t == null) return;
                    setState(() {
                      final len = _end.difference(_start);
                      _start = DateTime(
                          _start.year, _start.month, _start.day, t.hour, t.minute);
                      _end = _start.add(len);
                    });
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('–'),
              ),
              Expanded(
                child: OutlinedButton(
                  child: Text(formatTime(_end)),
                  onPressed: () async {
                    final t = await pickTime(context, TimeOfDay.fromDateTime(_end));
                    if (t == null) return;
                    setState(() {
                      _end = DateTime(
                          _start.year, _start.month, _start.day, t.hour, t.minute);
                      if (!_end.isAfter(_start)) {
                        _end = _end.add(const Duration(days: 1));
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Süre: ${formatDuration(duration)}',
                style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          Text('Alan', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          AreaPicker(value: _areaId, onChanged: (v) => setState(() => _areaId = v)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: openTasks.any((t) => t.id == _taskId) ? _taskId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bağlı görev'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Yok')),
              for (final t in openTasks)
                DropdownMenuItem(
                    value: t.id,
                    child: Text(t.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _taskId = v;
              final task = openTasks.where((t) => t.id == v).firstOrNull;
              if (task != null) {
                if (_title.text.trim().isEmpty) _title.text = task.title;
                _areaId = task.areaId ?? _areaId;
                _kind = 'task';
              }
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Notlar'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (_editing)
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Sil'),
                  onPressed: () async {
                    await ref.read(blocksRepoProvider).delete(widget.block!.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Vazgeç')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: _save, child: Text(_editing ? 'Kaydet' : 'Ekle')),
            ],
          ),
        ],
      ),
    );
  }
}
