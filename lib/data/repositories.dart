import 'package:drift/drift.dart';

import '../core/dates.dart';
import 'database.dart';

/// Tüm depoların ortak yardımcıları: her yazma `updated_at` ve `dirty`
/// alanlarını günceller ve senkronizasyonu tetikler.
abstract class _Repo {
  _Repo(this.db);
  final AppDatabase db;

  DateTime get _now => DateTime.now();

  /// Düzenleme zaman damgası: en az bir önceki sürümden 1 ms sonra.
  /// Böylece saati geride kalan bir cihazda yapılan düzenleme de, gördüğü
  /// sürümden her zaman daha yeni sayılır.
  Future<DateTime> _stamp(String table, String id) async {
    final now = _now;
    final row = await db
        .customSelect('SELECT updated_at FROM $table WHERE id = ?',
            variables: [Variable.withString(id)])
        .getSingleOrNull();
    if (row == null) return now;
    final previous = row.read<DateTime>('updated_at');
    return now.isAfter(previous)
        ? now
        : previous.add(const Duration(milliseconds: 1));
  }

  T _done<T>(T value) {
    db.notifyLocalWrite();
    return value;
  }
}

// ---------------------------------------------------------------------------

class AreasRepository extends _Repo {
  AreasRepository(super.db);

  Stream<List<Area>> watchAll() => (db.select(db.areas)
        ..where((a) => a.deleted.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
      .watch();

  Future<String> create({
    required String name,
    required int color,
    String icon = '',
    String kind = 'other',
    int sortOrder = 100,
  }) async {
    final id = newId();
    final now = _now;
    await db.into(db.areas).insert(AreasCompanion.insert(
          id: id,
          name: name,
          color: color,
          icon: Value(icon),
          kind: Value(kind),
          sortOrder: Value(sortOrder),
          createdAt: now,
          updatedAt: now,
        ));
    return _done(id);
  }

  Future<void> save(String id, AreasCompanion changes) async {
    final stamp = await _stamp(db.areas.actualTableName, id);
    await (db.update(db.areas)..where((a) => a.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(stamp), dirty: const Value(true)));
    _done(null);
  }

  Future<void> delete(String id) =>
      save(id, const AreasCompanion(deleted: Value(true)));
}

// ---------------------------------------------------------------------------

class TasksRepository extends _Repo {
  TasksRepository(super.db);

  /// Üst düzey görevler (alt görevler hariç).
  Stream<List<Task>> watchTopLevel({bool includeDone = false}) {
    final q = db.select(db.tasks)
      ..where((t) => t.deleted.equals(false) & t.parentId.isNull());
    if (!includeDone) q.where((t) => t.status.equals('todo'));
    q.orderBy([
      (t) => OrderingTerm(expression: t.dueAt, nulls: NullsOrder.last),
      (t) => OrderingTerm.desc(t.priority),
      (t) => OrderingTerm.asc(t.createdAt),
    ]);
    return q.watch();
  }

  /// Belirli bir tarihten sonra tamamlanan üst düzey görevler.
  Stream<List<Task>> watchCompletedSince(DateTime since) => (db.select(db.tasks)
        ..where((t) =>
            t.deleted.equals(false) &
            t.parentId.isNull() &
            t.status.equals('done') &
            t.completedAt.isBiggerOrEqualValue(since))
        ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
      .watch();

  Stream<Task?> watchOne(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  Stream<List<Task>> watchSubtasks(String parentId) => (db.select(db.tasks)
        ..where((t) => t.deleted.equals(false) & t.parentId.equals(parentId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
      .watch();

  /// Ebeveyn kimliğine göre (tamamlanan, toplam) alt görev sayıları.
  Stream<Map<String, (int, int)>> watchSubtaskCounts() {
    return (db.select(db.tasks)
          ..where((t) => t.deleted.equals(false) & t.parentId.isNotNull()))
        .watch()
        .map((rows) {
      final counts = <String, (int, int)>{};
      for (final t in rows) {
        final (done, total) = counts[t.parentId!] ?? (0, 0);
        counts[t.parentId!] = (done + (t.status == 'done' ? 1 : 0), total + 1);
      }
      return counts;
    });
  }

  Stream<List<Task>> watchByGoal(String goalId) => (db.select(db.tasks)
        ..where((t) => t.deleted.equals(false) & t.goalId.equals(goalId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.status),
          (t) => OrderingTerm(expression: t.dueAt, nulls: NullsOrder.last),
        ]))
      .watch();

  Future<Task?> getOne(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> create({
    required String title,
    String? areaId,
    String? goalId,
    String? parentId,
    String notes = '',
    int priority = 0,
    bool important = false,
    bool urgent = false,
    DateTime? dueAt,
    bool dueHasTime = false,
    int? estimateMinutes,
    String? recurrence,
    int sortOrder = 0,
  }) async {
    final id = newId();
    final now = _now;
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: id,
          title: title,
          areaId: Value(areaId),
          goalId: Value(goalId),
          parentId: Value(parentId),
          notes: Value(notes),
          priority: Value(priority),
          important: Value(important),
          urgent: Value(urgent),
          dueAt: Value(dueAt),
          dueHasTime: Value(dueHasTime),
          estimateMinutes: Value(estimateMinutes),
          recurrence: Value(recurrence),
          sortOrder: Value(sortOrder),
          createdAt: now,
          updatedAt: now,
        ));
    return _done(id);
  }

  Future<void> save(String id, TasksCompanion changes) async {
    final stamp = await _stamp(db.tasks.actualTableName, id);
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(stamp), dirty: const Value(true)));
    _done(null);
  }

  /// Görevi tamamlar / geri alır. Tekrarlayan bir görev tamamlandığında
  /// bir sonraki tekrarı oluşturulur.
  Future<void> setDone(Task task, bool done) async {
    final now = _now;
    await db.transaction(() async {
      await save(
        task.id,
        TasksCompanion(
          status: Value(done ? 'done' : 'todo'),
          completedAt: Value(done ? now : null),
        ),
      );
      if (done && task.status != 'done' && task.recurrence != null) {
        final next = nextOccurrence(task.dueAt ?? now, task.recurrence!);
        await create(
          title: task.title,
          areaId: task.areaId,
          goalId: task.goalId,
          notes: task.notes,
          priority: task.priority,
          important: task.important,
          urgent: task.urgent,
          dueAt: next,
          dueHasTime: task.dueHasTime,
          estimateMinutes: task.estimateMinutes,
          recurrence: task.recurrence,
        );
      }
    });
  }

  Future<void> delete(String id) async {
    final now = _now;
    await db.transaction(() async {
      await (db.update(db.tasks)
            ..where((t) => t.id.equals(id) | t.parentId.equals(id)))
          .write(TasksCompanion(
        deleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
    });
    _done(null);
  }
}

/// Tekrarlayan görevin bir sonraki tarihi.
DateTime nextOccurrence(DateTime from, String recurrence) {
  switch (recurrence) {
    case 'daily':
      return addDays(from, 1);
    case 'weekdays':
      var d = addDays(from, 1);
      while (d.weekday > DateTime.friday) {
        d = addDays(d, 1);
      }
      return d;
    case 'weekly':
      return addDays(from, 7);
    case 'monthly':
      final lastDay = DateTime(from.year, from.month + 2, 0).day;
      return DateTime(from.year, from.month + 1,
          from.day > lastDay ? lastDay : from.day, from.hour, from.minute);
    default:
      return addDays(from, 1);
  }
}

// ---------------------------------------------------------------------------

class BlocksRepository extends _Repo {
  BlocksRepository(super.db);

  /// [start, end) aralığıyla kesişen bloklar.
  Stream<List<TimeBlock>> watchRange(DateTime start, DateTime end) =>
      (db.select(db.blocks)
            ..where((b) =>
                b.deleted.equals(false) &
                b.startAt.isSmallerThanValue(end) &
                b.endAt.isBiggerThanValue(start))
            ..orderBy([(b) => OrderingTerm.asc(b.startAt)]))
          .watch();

  Future<List<TimeBlock>> getRange(DateTime start, DateTime end) =>
      (db.select(db.blocks)
            ..where((b) =>
                b.deleted.equals(false) &
                b.startAt.isSmallerThanValue(end) &
                b.endAt.isBiggerThanValue(start))
            ..orderBy([(b) => OrderingTerm.asc(b.startAt)]))
          .get();

  Future<String> create({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? areaId,
    String? taskId,
    String kind = 'event',
    String notes = '',
    int? color,
  }) async {
    final id = newId();
    final now = _now;
    await db.into(db.blocks).insert(BlocksCompanion.insert(
          id: id,
          title: title,
          startAt: startAt,
          endAt: endAt,
          areaId: Value(areaId),
          taskId: Value(taskId),
          kind: Value(kind),
          notes: Value(notes),
          color: Value(color),
          createdAt: now,
          updatedAt: now,
        ));
    return _done(id);
  }

  Future<void> save(String id, BlocksCompanion changes) async {
    final stamp = await _stamp(db.blocks.actualTableName, id);
    await (db.update(db.blocks)..where((b) => b.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(stamp), dirty: const Value(true)));
    _done(null);
  }

  Future<void> delete(String id) =>
      save(id, const BlocksCompanion(deleted: Value(true)));
}

// ---------------------------------------------------------------------------

class TimeEntriesRepository extends _Repo {
  TimeEntriesRepository(super.db);

  Stream<List<TimeEntry>> watchRange(DateTime start, DateTime end) =>
      (db.select(db.timeEntries)
            ..where((e) =>
                e.deleted.equals(false) &
                e.startAt.isSmallerThanValue(end) &
                (e.endAt.isNull() | e.endAt.isBiggerThanValue(start)))
            ..orderBy([(e) => OrderingTerm.desc(e.startAt)]))
          .watch();

  Future<List<TimeEntry>> getRange(DateTime start, DateTime end) =>
      (db.select(db.timeEntries)
            ..where((e) =>
                e.deleted.equals(false) &
                e.startAt.isSmallerThanValue(end) &
                (e.endAt.isNull() | e.endAt.isBiggerThanValue(start))))
          .get();

  Stream<List<TimeEntry>> watchByTask(String taskId) =>
      (db.select(db.timeEntries)
            ..where((e) => e.deleted.equals(false) & e.taskId.equals(taskId)))
          .watch();

  Future<String> add({
    required DateTime startAt,
    required DateTime endAt,
    String? taskId,
    String? areaId,
    String kind = 'manual',
    String note = '',
  }) async {
    final id = newId();
    final now = _now;
    await db.into(db.timeEntries).insert(TimeEntriesCompanion.insert(
          id: id,
          startAt: startAt,
          endAt: Value(endAt),
          taskId: Value(taskId),
          areaId: Value(areaId),
          kind: Value(kind),
          note: Value(note),
          createdAt: now,
          updatedAt: now,
        ));
    return _done(id);
  }

  Future<void> save(String id, TimeEntriesCompanion changes) async {
    final stamp = await _stamp(db.timeEntries.actualTableName, id);
    await (db.update(db.timeEntries)..where((e) => e.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(stamp), dirty: const Value(true)));
    _done(null);
  }

  Future<void> delete(String id) =>
      save(id, const TimeEntriesCompanion(deleted: Value(true)));
}

// ---------------------------------------------------------------------------

class HabitsRepository extends _Repo {
  HabitsRepository(super.db);

  Stream<List<Habit>> watchAll({bool includeArchived = false}) {
    final q = db.select(db.habits)..where((h) => h.deleted.equals(false));
    if (!includeArchived) q.where((h) => h.archived.equals(false));
    q.orderBy([
      (h) => OrderingTerm.asc(h.sortOrder),
      (h) => OrderingTerm.asc(h.createdAt),
    ]);
    return q.watch();
  }

  /// [fromDay, toDay] (dahil) aralığındaki kayıtlar; anahtar `habitId_gün`.
  Stream<Map<String, int>> watchLogs(DateTime fromDay, DateTime toDay) {
    final from = dayKey(fromDay);
    final to = dayKey(toDay);
    return (db.select(db.habitLogs)
          ..where((l) =>
              l.deleted.equals(false) &
              l.day.isBiggerOrEqualValue(from) &
              l.day.isSmallerOrEqualValue(to)))
        .watch()
        .map((rows) => {for (final l in rows) '${l.habitId}_${l.day}': l.count});
  }

  Future<String> create({
    required String name,
    required int color,
    String icon = '',
    String? areaId,
    int targetPerDay = 1,
    int weekdays = 127,
  }) async {
    final id = newId();
    final now = _now;
    await db.into(db.habits).insert(HabitsCompanion.insert(
          id: id,
          name: name,
          color: color,
          icon: Value(icon),
          areaId: Value(areaId),
          targetPerDay: Value(targetPerDay),
          weekdays: Value(weekdays),
          createdAt: now,
          updatedAt: now,
        ));
    return _done(id);
  }

  Future<void> save(String id, HabitsCompanion changes) async {
    final stamp = await _stamp(db.habits.actualTableName, id);
    await (db.update(db.habits)..where((h) => h.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(stamp), dirty: const Value(true)));
    _done(null);
  }

  Future<void> delete(String id) =>
      save(id, const HabitsCompanion(deleted: Value(true)));

  Future<void> setCount(String habitId, DateTime day, int count) async {
    final key = dayKey(day);
    final id = '${habitId}_$key';
    final now = await _stamp(db.habitLogs.actualTableName, id);
    await db.into(db.habitLogs).insertOnConflictUpdate(HabitLogsCompanion.insert(
          id: id,
          habitId: habitId,
          day: key,
          count: Value(count < 0 ? 0 : count),
          createdAt: now,
          updatedAt: now,
          deleted: const Value(false),
          dirty: const Value(true),
        ));
    _done(null);
  }
}

/// Bugünden geriye doğru kesintisiz tamamlanan (planlı) gün sayısı.
/// Bugün henüz tamamlanmadıysa seri dünden itibaren sayılır.
int habitStreak(Habit habit, Map<String, int> logs, DateTime today) {
  var streak = 0;
  var day = startOfDay(today);
  final created = startOfDay(habit.createdAt.toLocal());
  for (var i = 0; i < 366; i++) {
    if (day.isBefore(created) && i > 0) break;
    if (weekdayInMask(habit.weekdays, day)) {
      final count = logs['${habit.id}_${dayKey(day)}'] ?? 0;
      if (count >= habit.targetPerDay) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

// ---------------------------------------------------------------------------

class GoalsRepository extends _Repo {
  GoalsRepository(super.db);

  Stream<List<Goal>> watchAll() => (db.select(db.goals)
        ..where((g) => g.deleted.equals(false))
        ..orderBy([
          (g) => OrderingTerm.asc(g.status),
          (g) => OrderingTerm(expression: g.targetDate, nulls: NullsOrder.last),
        ]))
      .watch();

  Future<String> create({
    required String title,
    String? areaId,
    String description = '',
    DateTime? targetDate,
    String progressMode = 'tasks',
    double targetValue = 100,
    double currentValue = 0,
    String unit = '',
  }) async {
    final id = newId();
    final now = _now;
    await db.into(db.goals).insert(GoalsCompanion.insert(
          id: id,
          title: title,
          areaId: Value(areaId),
          description: Value(description),
          targetDate: Value(targetDate),
          progressMode: Value(progressMode),
          targetValue: Value(targetValue),
          currentValue: Value(currentValue),
          unit: Value(unit),
          createdAt: now,
          updatedAt: now,
        ));
    return _done(id);
  }

  Future<void> save(String id, GoalsCompanion changes) async {
    final stamp = await _stamp(db.goals.actualTableName, id);
    await (db.update(db.goals)..where((g) => g.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(stamp), dirty: const Value(true)));
    _done(null);
  }

  Future<void> delete(String id) =>
      save(id, const GoalsCompanion(deleted: Value(true)));
}
