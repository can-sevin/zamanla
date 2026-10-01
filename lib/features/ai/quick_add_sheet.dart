import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/ai_service.dart';
import '../../core/dates.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../settings/ai_settings_screen.dart';

Future<void> showQuickAdd(BuildContext context) =>
    showAdaptiveSheet<void>(context, (_) => const QuickAddSheet());

/// Doğal dille hızlı ekleme: "yarın 14:00 müşteri toplantısı, cuma rapor".
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  List<QuickAddItem>? _items;
  List<bool> _selected = [];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _parse(AiService ai) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final areas = ref.read(areasProvider).value ?? const <Area>[];
      final items = await ai.parseQuickAdd(
        text,
        now: DateTime.now(),
        areas: [
          for (final a in areas) AiArea(id: a.id, name: a.name, kind: a.kind),
        ],
      );
      setState(() {
        _items = items;
        _selected = List.filled(items.length, true);
        if (items.isEmpty) _error = 'Eklenecek bir şey bulunamadı.';
      });
    } on AiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPlain() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await ref.read(tasksRepoProvider).create(
          title: text,
          areaId: ref.read(areaFilterProvider) ?? workAreaId,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _commit() async {
    final items = _items!;
    final tasks = ref.read(tasksRepoProvider);
    final blocks = ref.read(blocksRepoProvider);
    var count = 0;
    for (var i = 0; i < items.length; i++) {
      if (!_selected[i]) continue;
      final it = items[i];
      if (it.isEvent) {
        await blocks.create(
          title: it.title,
          startAt: it.start!,
          endAt: it.end!,
          areaId: it.areaId,
          notes: it.notes,
          kind: 'event',
        );
      } else {
        await tasks.create(
          title: it.title,
          areaId: it.areaId,
          notes: it.notes,
          dueAt: it.dueAt,
          dueHasTime: it.dueHasTime,
          estimateMinutes: it.estimateMinutes,
          priority: it.priority,
          important: it.important,
          urgent: it.urgent,
        );
      }
      count++;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, '$count öğe eklendi.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiAsync = ref.watch(aiServiceProvider);
    final ai = aiAsync.value;
    final areas = ref.watch(areaMapProvider);

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
              Text('Hızlı ekle', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Aklındakini yaz; görevlere ve takvim etkinliklerine ayırayım.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'ör. Yarın 14:00 müşteriyle toplantı 1 saat, cuma rapor teslimi önemli, akşam annemi ara',
            ),
          ),
          const SizedBox(height: 12),
          if (aiAsync.isLoading)
            const LinearProgressIndicator()
          else if (ai == null) ...[
            Text(
              'Yapay zeka ayarlı değil. Metni tek bir görev olarak ekleyebilir '
              'ya da ayarlardan bir sağlayıcı bağlayabilirsin.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(MaterialPageRoute<void>(
                        builder: (_) => const AiSettingsScreen()));
                  },
                  child: const Text('Yapay zekayı ayarla'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _addPlain, child: const Text('Görev olarak ekle')),
              ],
            ),
          ] else if (_items == null || _items!.isEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: _busy ? null : _addPlain,
                    child: const Text('Olduğu gibi ekle')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _parse(ai),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: const Text('Ayrıştır'),
                ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_items != null && _items!.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (var i = 0; i < _items!.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected[i],
                onChanged: (v) => setState(() => _selected[i] = v ?? false),
                secondary: Icon(_items![i].isEvent
                    ? Icons.event
                    : Icons.check_circle_outline),
                title: Text(_items![i].title),
                subtitle: Text(_describe(_items![i], areas)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _items = null),
                  child: const Text('Geri'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selected.contains(true) ? _commit : null,
                  child: Text('Ekle (${_selected.where((s) => s).length})'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _describe(QuickAddItem it, Map<String, Area> areas) {
    final parts = <String>[
      it.isEvent ? 'Etkinlik' : 'Görev',
      if (areas[it.areaId] != null) areas[it.areaId]!.name,
      if (it.isEvent)
        '${formatRelativeDay(it.start!)} ${formatTime(it.start!)}–${formatTime(it.end!)}'
      else if (it.dueAt != null)
        formatDue(it.dueAt!, it.dueHasTime),
      if (it.estimateMinutes != null)
        formatDuration(Duration(minutes: it.estimateMinutes!)),
      if (it.important) 'önemli',
      if (it.urgent) 'acil',
    ];
    return parts.join(' · ');
  }
}
