import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/ai_service.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../settings/ai_settings_screen.dart';
import 'ai_context.dart';

Future<void> showPlanDay(BuildContext context, DateTime day) =>
    showAdaptiveSheet<void>(context, (_) => PlanDaySheet(day: startOfDay(day)));

/// Yapay zekanın, açık görevleri gün içindeki boşluklara yerleştirdiği
/// zaman bloğu önerisi. Kullanıcı onaylarsa takvime eklenir.
class PlanDaySheet extends ConsumerStatefulWidget {
  const PlanDaySheet({super.key, required this.day});
  final DateTime day;

  @override
  ConsumerState<PlanDaySheet> createState() => _PlanDaySheetState();
}

class _PlanDaySheetState extends ConsumerState<PlanDaySheet> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  DayPlan? _plan;
  List<bool> _selected = [];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _generate(AiService ai) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = ref.read(settingsProvider);
      final filter = ref.read(areaFilterProvider);
      final areas = ref.read(areaMapProvider);
      final goals = {
        for (final g in ref.read(goalsProvider).value ?? const <Goal>[]) g.id: g,
      };
      final open = (await ref.read(openTasksProvider.future))
          .where((t) => matchesArea(filter, t.areaId))
          .toList();
      final existing = await ref
          .read(blocksRepoProvider)
          .getRange(widget.day, endOfDay(widget.day));
      final plan = await ai.planDay(
        day: widget.day,
        now: DateTime.now(),
        dayStart: widget.day.add(Duration(minutes: settings.workStartMinutes)),
        dayEnd: widget.day.add(Duration(minutes: settings.workEndMinutes)),
        tasks: tasksForPlanning(open, areas, goals, widget.day),
        busy: [
          for (final b in existing)
            AiBusySlot(title: b.title, start: b.startAt, end: b.endAt),
        ],
        note: _note.text,
      );
      setState(() {
        _plan = plan;
        _selected = List.filled(plan.blocks.length, true);
        if (plan.blocks.isEmpty) {
          _error = plan.summary.isEmpty ? 'Yerleştirilecek blok yok.' : null;
        }
      });
    } on AiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final plan = _plan!;
    final tasks = {
      for (final t in ref.read(openTasksProvider).value ?? const <Task>[]) t.id: t,
    };
    final repo = ref.read(blocksRepoProvider);
    var count = 0;
    for (var i = 0; i < plan.blocks.length; i++) {
      if (!_selected[i]) continue;
      final b = plan.blocks[i];
      await repo.create(
        title: b.title,
        startAt: b.start,
        endAt: b.end,
        taskId: b.taskId,
        areaId: tasks[b.taskId]?.areaId ?? ref.read(areaFilterProvider),
        kind: b.kind,
        notes: b.reason,
      );
      count++;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, '$count blok takvime eklendi.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiAsync = ref.watch(aiServiceProvider);
    final ai = aiAsync.value;
    final settings = ref.watch(settingsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${formatRelativeDay(widget.day)} için plan',
                    style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Çalışma saatlerin: ${settings.workStart.format(context)} – '
            '${settings.workEnd.format(context)}. Mevcut etkinliklerin korunur.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (aiAsync.isLoading)
            const LinearProgressIndicator()
          else if (ai == null)
            AiNotConfigured(onOpenSettings: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute<void>(
                  builder: (_) => const AiSettingsScreen()));
            })
          else if (_plan == null || _plan!.blocks.isEmpty) ...[
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'İsteğe bağlı not: "16:00\'da çıkmam lazım", "bugün enerjim düşük"…',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _generate(ai),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'Planlanıyor…' : 'Plan oluştur'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_plan != null) ...[
            if (_plan!.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_plan!.summary),
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (var i = 0; i < _plan!.blocks.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected[i],
                onChanged: (v) => setState(() => _selected[i] = v ?? false),
                title: Text(_plan!.blocks[i].title),
                subtitle: Text([
                  '${formatTime(_plan!.blocks[i].start)}–${formatTime(_plan!.blocks[i].end)}',
                  blockKinds[_plan!.blocks[i].kind] ?? '',
                  if (_plan!.blocks[i].reason.isNotEmpty) _plan!.blocks[i].reason,
                ].join(' · ')),
              ),
            if (_plan!.blocks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy || ai == null ? null : () => _generate(ai),
                    child: const Text('Yeniden oluştur'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.contains(true) ? _apply : null,
                    child: Text('Takvime ekle (${_selected.where((s) => s).length})'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
