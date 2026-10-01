import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../ai/ai_service.dart';
import '../../core/dates.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';

/// Açık görevleri yapay zeka planlayıcısı için hazırlar: önce gecikmiş ve
/// yakın tarihli, sonra önemli/öncelikli olanlar.
List<AiTaskInfo> tasksForPlanning(
  List<Task> open,
  Map<String, Area> areas,
  Map<String, Goal> goals,
  DateTime day, {
  int limit = 40,
}) {
  final horizon = addDays(day, 7);
  int score(Task t) {
    var s = t.priority * 10 + (t.important ? 15 : 0) + (t.urgent ? 12 : 0);
    if (t.dueAt != null) {
      if (!t.dueAt!.isAfter(endOfDay(day))) {
        s += 50;
      } else if (t.dueAt!.isBefore(horizon)) {
        s += 20;
      }
    }
    return s;
  }

  final sorted = [...open]..sort((a, b) => score(b).compareTo(score(a)));
  return [
    for (final t in sorted.take(limit))
      AiTaskInfo(
        id: t.id,
        title: t.title,
        areaName: areas[t.areaId]?.name,
        dueAt: t.dueAt,
        dueHasTime: t.dueHasTime,
        estimateMinutes: t.estimateMinutes,
        priority: t.priority,
        important: t.important,
        urgent: t.urgent,
        goalTitle: goals[t.goalId]?.title,
      ),
  ];
}

/// Asistan sohbeti için kullanıcının verilerinin kısa, metin tabanlı özeti.
Future<String> buildAssistantSnapshot(AppDatabase db, DateTime now) async {
  final today = startOfDay(now);
  final weekAgo = addDays(today, -6);
  final fmtDay = DateFormat('EEE d MMM', 'tr');
  final fmtDate = DateFormat('yyyy-MM-dd');

  final areas = {
    for (final a in await (db.select(db.areas)
          ..where((a) => a.deleted.equals(false)))
        .get())
      a.id: a,
  };
  String areaName(String? id) => areas[id]?.name ?? 'Alansız';

  final open = await (db.select(db.tasks)
        ..where((t) =>
            t.deleted.equals(false) &
            t.status.equals('todo') &
            t.parentId.isNull())
        ..orderBy([
          (t) => OrderingTerm(expression: t.dueAt, nulls: NullsOrder.last),
          (t) => OrderingTerm.desc(t.priority),
        ])
        ..limit(60))
      .get();
  final done = await (db.select(db.tasks)
        ..where((t) =>
            t.deleted.equals(false) &
            t.status.equals('done') &
            t.completedAt.isBiggerOrEqualValue(weekAgo))
        ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
      .get();
  final blocks =
      await BlocksRepository(db).getRange(today, addDays(today, 2));
  final entries =
      await TimeEntriesRepository(db).getRange(weekAgo, endOfDay(today));
  final habits = await (db.select(db.habits)
        ..where((h) => h.deleted.equals(false) & h.archived.equals(false)))
      .get();
  final logs = {
    for (final l in await (db.select(db.habitLogs)
          ..where((l) =>
              l.deleted.equals(false) &
              l.day.isBiggerOrEqualValue(dayKey(addDays(today, -60)))))
        .get())
      '${l.habitId}_${l.day}': l.count,
  };
  final goals = await (db.select(db.goals)
        ..where((g) => g.deleted.equals(false) & g.status.equals('active')))
      .get();

  final b = StringBuffer();
  b.writeln('Areas: ${areas.values.map((a) => '${a.name} (${a.kind})').join(', ')}');

  b.writeln('\nOpen tasks (${open.length}${open.length == 60 ? '+' : ''}):');
  for (final t in open) {
    final due = t.dueAt == null
        ? ''
        : ' due ${fmtDate.format(t.dueAt!)}${t.dueHasTime ? ' ${formatTime(t.dueAt!)}' : ''}';
    final flags = [
      if (t.priority > 0) 'p${t.priority}',
      if (t.important) 'important',
      if (t.urgent) 'urgent',
      if (t.estimateMinutes != null) '~${t.estimateMinutes}m',
    ].join(' ');
    b.writeln('- [${areaName(t.areaId)}] ${t.title}$due${flags.isEmpty ? '' : ' ($flags)'}');
  }

  b.writeln('\nCalendar today and tomorrow:');
  if (blocks.isEmpty) b.writeln('- (empty)');
  for (final x in blocks) {
    b.writeln('- ${fmtDay.format(x.startAt)} ${formatTime(x.startAt)}-'
        '${formatTime(x.endAt)} ${x.title} [${areaName(x.areaId)}, ${x.kind}]');
  }

  b.writeln('\nTracked focus time, last 7 days:');
  final perDay = <String, Map<String, int>>{};
  for (final e in entries) {
    if (e.endAt == null) continue;
    final key = fmtDay.format(e.startAt);
    final m = perDay.putIfAbsent(key, () => {});
    m[areaName(e.areaId)] =
        (m[areaName(e.areaId)] ?? 0) + e.endAt!.difference(e.startAt).inMinutes;
  }
  if (perDay.isEmpty) b.writeln('- (no tracked time)');
  for (var d = weekAgo; !d.isAfter(today); d = addDays(d, 1)) {
    final m = perDay[fmtDay.format(d)];
    if (m == null) continue;
    b.writeln('- ${fmtDay.format(d)}: ${m.entries.map((e) => '${e.key} ${formatDuration(Duration(minutes: e.value))}').join(', ')}');
  }

  b.writeln('\nCompleted in last 7 days (${done.length}):');
  for (final t in done.take(20)) {
    b.writeln('- ${fmtDay.format(t.completedAt!)}: [${areaName(t.areaId)}] ${t.title}');
  }

  b.writeln('\nHabits:');
  if (habits.isEmpty) b.writeln('- (none)');
  for (final h in habits) {
    final week = [
      for (var d = weekAgo; !d.isAfter(today); d = addDays(d, 1))
        (logs['${h.id}_${dayKey(d)}'] ?? 0) >= h.targetPerDay ? '✓' : '·',
    ].join();
    b.writeln('- ${h.name}: streak ${habitStreak(h, logs, today)} days, '
        'last 7 days $week, target ${h.targetPerDay}/day');
  }

  b.writeln('\nActive goals:');
  if (goals.isEmpty) b.writeln('- (none)');
  for (final g in goals) {
    final target = g.targetDate == null ? '' : ' by ${fmtDate.format(g.targetDate!)}';
    final progress = g.progressMode == 'manual'
        ? '${g.currentValue}/${g.targetValue} ${g.unit}'
        : 'task-based';
    b.writeln('- [${areaName(g.areaId)}] ${g.title}$target ($progress)');
  }
  return b.toString();
}
