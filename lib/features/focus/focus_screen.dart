import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import 'focus_controller.dart';

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Odak')),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 3, child: _TimerPanel()),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: _TodayEntries()),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _TimerPanel(),
                const Divider(height: 32),
                _TodayEntries(shrinkWrap: true),
              ],
            ),
    );
  }
}

class _TimerPanel extends ConsumerStatefulWidget {
  const _TimerPanel();

  @override
  ConsumerState<_TimerPanel> createState() => _TimerPanelState();
}

class _TimerPanelState extends ConsumerState<_TimerPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Çalışırken her saniye yeniden çiz; süre duvar saatinden hesaplanır.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(focusProvider).running) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(focusProvider);
    final ctrl = ref.read(focusProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final now = DateTime.now();
    final pomodoro = state.mode == FocusMode.pomodoro;

    final total = Duration(
      minutes: switch (state.phase) {
        FocusPhase.work => settings.pomodoroWork,
        FocusPhase.shortBreak => settings.pomodoroShortBreak,
        FocusPhase.longBreak => settings.pomodoroLongBreak,
      },
    );
    final remaining = state.remainingAt(now);
    final shown = pomodoro
        ? (remaining.isNegative ? Duration.zero : remaining)
        : state.elapsedAt(now);
    final progress = pomodoro && total.inSeconds > 0
        ? 1 - shown.inSeconds / total.inSeconds
        : (shown.inSeconds % 3600) / 3600;
    final color = state.phase == FocusPhase.work || !pomodoro
        ? theme.colorScheme.primary
        : const Color(0xFF2E9D6A);

    final tasks = ref.watch(openTasksProvider).value ?? const <Task>[];
    final task = tasks.where((t) => t.id == state.taskId).firstOrNull;
    final areas = ref.watch(areasProvider).value ?? const <Area>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              SegmentedButton<FocusMode>(
                segments: const [
                  ButtonSegment(
                      value: FocusMode.pomodoro,
                      icon: Icon(Icons.timer_outlined),
                      label: Text('Pomodoro')),
                  ButtonSegment(
                      value: FocusMode.stopwatch,
                      icon: Icon(Icons.av_timer),
                      label: Text('Kronometre')),
                ],
                selected: {state.mode},
                onSelectionChanged: state.running
                    ? null
                    : (s) => ctrl.setMode(s.first),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _RingPainter(
                        progress: progress.clamp(0, 1).toDouble(),
                        color: color,
                        track: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pomodoro ? state.phase.label : 'Geçen süre',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: color),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatClock(shown),
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (pomodoro)
                            Text(
                              '${state.completedPomodoros} pomodoro tamamlandı',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    tooltip: 'Sıfırla',
                    onPressed: ctrl.reset,
                    icon: const Icon(Icons.restart_alt),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 64,
                    width: 160,
                    child: FilledButton.icon(
                      onPressed: state.running ? ctrl.pause : ctrl.start,
                      icon: Icon(state.running ? Icons.pause : Icons.play_arrow),
                      label: Text(state.running ? 'Duraklat' : 'Başlat',
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.outlined(
                    tooltip: 'Sonraki aşama',
                    onPressed: pomodoro ? ctrl.skip : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Neye odaklanıyorsun?',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        key: ValueKey(state.taskId),
                        initialValue: task?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Görev'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Görev seçilmedi')),
                          for (final t in tasks)
                            DropdownMenuItem(
                                value: t.id,
                                child: Text(t.title,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (id) {
                          final t = tasks.where((t) => t.id == id).firstOrNull;
                          ctrl.selectTask(id, t?.areaId ?? state.areaId);
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final a in areas)
                            ChoiceChip(
                              avatar: a.icon.isEmpty ? null : Text(a.icon),
                              label: Text(a.name),
                              selected: state.areaId == a.id,
                              onSelected: (sel) =>
                                  ctrl.selectTask(state.taskId, sel ? a.id : null),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false,
        paint..color = track);
    canvas.drawArc(rect.deflate(stroke / 2), -math.pi / 2,
        math.pi * 2 * progress, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

class _TodayEntries extends ConsumerWidget {
  _TodayEntries({this.shrinkWrap = false});
  final bool shrinkWrap;
  final DateTime _day = startOfDay(DateTime.now());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final day = ref.watch(todayProvider);
    final entries =
        ref.watch(entriesInRangeProvider((day, endOfDay(day)))).value ??
            const <TimeEntry>[];
    final tasks = {
      for (final t in ref.watch(openTasksProvider).value ?? const <Task>[]) t.id: t,
      for (final t in ref.watch(completedRecentlyProvider).value ?? const <Task>[])
        t.id: t,
    };
    final areas = ref.watch(areaMapProvider);
    final total = entries.fold(
        Duration.zero,
        (s, e) => s + ((e.endAt ?? DateTime.now()).difference(e.startAt)));

    final children = <Widget>[
      ListTile(
        title: Text('Bugün', style: theme.textTheme.titleMedium),
        subtitle: Text('Toplam ${formatDuration(total)} · ${entries.length} kayıt'),
        trailing: TextButton.icon(
          onPressed: () => showManualEntryDialog(context, ref, _day),
          icon: const Icon(Icons.add),
          label: const Text('Elle ekle'),
        ),
      ),
      if (entries.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Henüz kayıt yok. Zamanlayıcıyı başlattığında burada görünecek.',
              textAlign: TextAlign.center),
        ),
      for (final e in entries)
        ListTile(
          leading: Icon(
            switch (e.kind) {
              'pomodoro' => Icons.timer_outlined,
              'stopwatch' => Icons.av_timer,
              _ => Icons.edit_calendar_outlined,
            },
            color: areas[e.areaId] == null
                ? theme.colorScheme.outline
                : Color(areas[e.areaId]!.color),
          ),
          title: Text(tasks[e.taskId]?.title ??
              (e.note.isNotEmpty ? e.note : (areas[e.areaId]?.name ?? 'Odak oturumu'))),
          subtitle: Text(
              '${formatTime(e.startAt)} – ${e.endAt == null ? '…' : formatTime(e.endAt!)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatDuration(
                  (e.endAt ?? DateTime.now()).difference(e.startAt))),
              IconButton(
                tooltip: 'Sil',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref.read(timeEntriesRepoProvider).delete(e.id),
              ),
            ],
          ),
        ),
    ];
    return shrinkWrap
        ? Column(children: children)
        : ListView(padding: const EdgeInsets.only(top: 8), children: children);
  }
}

Future<void> showManualEntryDialog(
    BuildContext context, WidgetRef ref, DateTime day) async {
  final now = DateTime.now();
  var start = isSameDay(day, now)
      ? now.subtract(const Duration(hours: 1))
      : day.add(const Duration(hours: 9));
  var end = start.add(const Duration(hours: 1));
  String? taskId;
  String? areaId = ref.read(areaFilterProvider) ?? workAreaId;
  final note = TextEditingController();
  final tasks = ref.read(openTasksProvider).value ?? const <Task>[];

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Zaman kaydı ekle'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: taskId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Görev'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Yok')),
                  for (final t in tasks)
                    DropdownMenuItem(
                        value: t.id,
                        child: Text(t.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  taskId = v;
                  areaId = tasks.where((t) => t.id == v).firstOrNull?.areaId ??
                      areaId;
                }),
              ),
              const SizedBox(height: 12),
              AreaPicker(value: areaId, onChanged: (v) => setState(() => areaId = v)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await pickTime(context, TimeOfDay.fromDateTime(start));
                        if (t != null) {
                          setState(() => start = DateTime(
                              start.year, start.month, start.day, t.hour, t.minute));
                        }
                      },
                      child: Text('Başlangıç ${formatTime(start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await pickTime(context, TimeOfDay.fromDateTime(end));
                        if (t != null) {
                          setState(() => end = DateTime(
                              start.year, start.month, start.day, t.hour, t.minute));
                        }
                      },
                      child: Text('Bitiş ${formatTime(end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(hintText: 'Not (isteğe bağlı)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () async {
              if (!end.isAfter(start)) return;
              await ref.read(timeEntriesRepoProvider).add(
                    startAt: start,
                    endAt: end,
                    taskId: taskId,
                    areaId: areaId,
                    note: note.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
}
