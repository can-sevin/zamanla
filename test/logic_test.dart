import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zamanla/core/dates.dart';
import 'package:zamanla/data/database.dart';
import 'package:zamanla/data/repositories.dart';
import 'package:zamanla/features/calendar/block_editor.dart';
import 'package:zamanla/features/calendar/calendar_screen.dart';
import 'package:zamanla/features/tasks/tasks_screen.dart';

TimeBlock _block(String id, DateTime start, DateTime end) => TimeBlock(
      id: id,
      createdAt: start,
      updatedAt: start,
      deleted: false,
      dirty: false,
      title: id,
      startAt: start,
      endAt: end,
      notes: '',
      kind: 'event',
    );

Task _task(String id, {DateTime? due}) => Task(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deleted: false,
      dirty: false,
      title: id,
      notes: '',
      priority: 0,
      important: false,
      urgent: false,
      dueAt: due,
      dueHasTime: false,
      status: 'todo',
      tags: '',
      sortOrder: 0,
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  group('tarih yardımcıları', () {
    test('hafta pazartesi başlar', () {
      expect(startOfWeek(DateTime(2026, 10, 4)), DateTime(2026, 9, 28)); // Pazar
      expect(startOfWeek(DateTime(2026, 9, 28, 15)), DateTime(2026, 9, 28));
    });

    test('süre biçimi', () {
      expect(formatDuration(const Duration(minutes: 85)), '1 sa 25 dk');
      expect(formatDuration(const Duration(minutes: 40)), '40 dk');
      expect(formatDuration(const Duration(hours: 2)), '2 sa');
      expect(formatClock(const Duration(minutes: 24, seconds: 5)), '24:05');
    });

    test('göreli gün', () {
      final now = DateTime(2026, 10, 1, 12);
      expect(formatRelativeDay(DateTime(2026, 10, 1), now: now), 'Bugün');
      expect(formatRelativeDay(DateTime(2026, 10, 2), now: now), 'Yarın');
      expect(formatRelativeDay(DateTime(2026, 9, 30), now: now), 'Dün');
    });
  });

  group('tekrarlayan görevler', () {
    test('sonraki tarih', () {
      final fri = DateTime(2026, 10, 2, 9); // Cuma
      expect(nextOccurrence(fri, 'daily'), DateTime(2026, 10, 3, 9));
      expect(nextOccurrence(fri, 'weekdays'), DateTime(2026, 10, 5, 9));
      expect(nextOccurrence(fri, 'weekly'), DateTime(2026, 10, 9, 9));
      expect(nextOccurrence(DateTime(2026, 1, 31), 'monthly'), DateTime(2026, 2, 28));
    });

    test('tamamlanınca bir sonraki tekrar oluşturulur', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TasksRepository(db);
      final id = await repo.create(
          title: 'Haftalık rapor', dueAt: DateTime(2026, 10, 2), recurrence: 'weekly');
      await repo.setDone((await repo.getOne(id))!, true);

      final all = await db.select(db.tasks).get();
      expect(all, hasLength(2));
      final next = all.firstWhere((t) => t.id != id);
      expect(next.status, 'todo');
      expect(next.dueAt, DateTime(2026, 10, 9));
      expect(next.recurrence, 'weekly');
    });
  });

  group('alışkanlık serisi', () {
    final habit = Habit(
      id: 'h',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      deleted: false,
      dirty: false,
      name: 'Okuma',
      icon: '',
      color: 0,
      targetPerDay: 1,
      weekdays: 127,
      archived: false,
      sortOrder: 0,
    );
    final today = DateTime(2026, 10, 1);

    test('bugün henüz yapılmadıysa dünden sayar', () {
      final logs = {'h_2026-09-30': 1, 'h_2026-09-29': 1, 'h_2026-09-27': 1};
      expect(habitStreak(habit, logs, today), 2);
    });

    test('bugün dahil', () {
      final logs = {'h_2026-10-01': 1, 'h_2026-09-30': 1};
      expect(habitStreak(habit, logs, today), 2);
    });

    test('planlanmamış günler seriyi bozmaz', () {
      // Yalnızca hafta içi (Pzt-Cum = bit 0..4)
      final weekdaysOnly = habit.copyWith(weekdays: 31);
      // 2026-10-01 Perşembe, 09-28 Pazartesi, 09-26/27 hafta sonu, 09-25 Cuma
      final logs = {
        'h_2026-10-01': 1,
        'h_2026-09-30': 1,
        'h_2026-09-29': 1,
        'h_2026-09-28': 1,
        'h_2026-09-25': 1,
      };
      expect(habitStreak(weekdaysOnly, logs, today), 5);
    });
  });

  group('takvim', () {
    final d = DateTime(2026, 10, 1);
    DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 1, h, m);

    test('çakışan bloklar yan yana şeritlere yerleşir', () {
      final lanes = layoutLanes([
        _block('a', at(9), at(10)),
        _block('b', at(9, 30), at(11)),
        _block('c', at(10), at(10, 30)),
        _block('d', at(12), at(13)),
      ]);
      final byId = {for (final (b, lane, count) in lanes) b.id: (lane, count)};
      expect(byId['a'], (0, 2));
      expect(byId['b'], (1, 2));
      expect(byId['c'], (0, 2), reason: 'a bitince aynı şeridi kullanır');
      expect(byId['d'], (0, 1), reason: 'ayrı küme');
    });

    test('boş aralık bulma', () {
      final blocks = [
        _block('a', at(9), at(10)),
        _block('b', at(10, 15), at(11)),
      ];
      expect(findFreeSlot(blocks, at(9), at(18), const Duration(minutes: 30)),
          at(11));
      expect(findFreeSlot(blocks, at(9), at(18), const Duration(minutes: 15)),
          at(10));
      expect(findFreeSlot(blocks, at(17, 50), at(18), const Duration(hours: 1)),
          isNull);
      expect(roundUpToQuarter(at(9, 1)), at(9, 15));
      expect(roundUpToQuarter(d), d);
    });
  });

  test('görev gruplama', () {
    final now = DateTime(2026, 10, 1, 10); // Perşembe
    final groups = groupTasksByDue([
      _task('gecikmis', due: DateTime(2026, 9, 29)),
      _task('bugun', due: DateTime(2026, 10, 1, 18)),
      _task('yarin', due: DateTime(2026, 10, 2)),
      _task('haftasonu', due: DateTime(2026, 10, 4)),
      _task('sonra', due: DateTime(2026, 10, 20)),
      _task('tarihsiz'),
    ], now);
    expect(groups.keys,
        ['Gecikmiş', 'Bugün', 'Yarın', 'Bu hafta', 'Daha sonra', 'Tarihsiz']);
    expect(groups['Bu hafta']!.single.id, 'haftasonu');
  });
}
