import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zamanla/data/database.dart';
import 'package:zamanla/data/repositories.dart';
import 'package:zamanla/data/sync_service.dart';

/// Supabase tablolarını ve `zamanla_touch_row` tetikleyicisini taklit eder.
class FakeRemote implements SyncRemote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  var _clock = DateTime.utc(2026, 1, 1);
  int upsertCalls = 0;

  /// Gönderim sırasında yerel düzenlemeyi taklit etmek için.
  Future<void> Function(String table)? duringUpsert;

  @override
  Future<Set<String>> upsert(String table, List<Map<String, dynamic>> rows) async {
    upsertCalls++;
    await duringUpsert?.call(table);
    final t = tables.putIfAbsent(table, () => {});
    final accepted = <String>{};
    for (final row in rows) {
      final id = row['id'] as String;
      final existing = t[id];
      if (existing != null &&
          DateTime.parse(row['updated_at'] as String)
              .isBefore(DateTime.parse(existing['updated_at'] as String))) {
        continue; // tetikleyici bayat yazmayı yok sayar
      }
      _clock = _clock.add(const Duration(milliseconds: 1));
      t[id] = {...row, 'server_updated_at': _clock.toIso8601String()};
      accepted.add(id);
    }
    return accepted;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchByIds(
          String table, List<String> ids) async =>
      [for (final id in ids) if (tables[table]?[id] != null) {...tables[table]![id]!}];

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, DateTime after, int limit) async {
    final rows = (tables[table]?.values ?? const <Map<String, dynamic>>[])
        .where((r) =>
            DateTime.parse(r['server_updated_at'] as String).isAfter(after))
        .toList()
      ..sort((a, b) => (a['server_updated_at'] as String)
          .compareTo(b['server_updated_at'] as String));
    return [for (final r in rows.take(limit)) {...r}];
  }
}

class MemoryCursors implements CursorStore {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class Device {
  Device(FakeRemote remote)
      : db = AppDatabase(NativeDatabase.memory()),
        cursors = MemoryCursors() {
    engine = SyncEngine(db: db, remote: remote, userId: 'u1', cursors: cursors);
  }

  final AppDatabase db;
  final MemoryCursors cursors;
  late final SyncEngine engine;

  TasksRepository get tasks => TasksRepository(db);
  AreasRepository get areas => AreasRepository(db);
  HabitsRepository get habits => HabitsRepository(db);

  Future<void> sync() => engine.run();

  Future<List<Task>> allTasks() => db.select(db.tasks).get();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeRemote remote;
  late Device phone;
  late Device pc;

  setUp(() {
    remote = FakeRemote();
    phone = Device(remote);
    pc = Device(remote);
  });

  tearDown(() async {
    await phone.db.close();
    await pc.db.close();
  });

  test('bir cihazda eklenen görev diğerine gelir ve kirli işareti kalkar', () async {
    final id = await phone.tasks.create(title: 'Sunum hazırla', areaId: workAreaId);
    await phone.sync();
    await pc.sync();

    final onPc = await pc.allTasks();
    expect(onPc.single.id, id);
    expect(onPc.single.title, 'Sunum hazırla');
    expect(onPc.single.dirty, isFalse);
    expect((await phone.allTasks()).single.dirty, isFalse);
    expect(remote.tables['tasks']![id]!['user_id'], 'u1');
    expect(remote.tables['tasks']![id]!.containsKey('dirty'), isFalse);
  });

  test('yeni kurulan cihazın varsayılan alanları eski düzenlemeyi ezmez', () async {
    await phone.areas.save(workAreaId, const AreasCompanion(name: Value('Ofis')));
    await phone.sync();

    final fresh = Device(remote);
    await fresh.sync();
    await phone.sync();

    final names = {
      for (final a in await fresh.db.select(fresh.db.areas).get()) a.id: a.name,
    };
    expect(names[workAreaId], 'Ofis');
    expect(remote.tables['areas']![workAreaId]!['name'], 'Ofis');
    await fresh.db.close();
  });

  test('çakışmada son düzenleme kazanır (senkron sırası fark etmez)', () async {
    final id = await phone.tasks.create(title: 'İlk');
    await phone.sync();
    await pc.sync();

    // İki cihaz çevrimdışıyken aynı görevi düzenler; PC daha sonra düzenler.
    await phone.tasks.save(id, const TasksCompanion(title: Value('Telefon')));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pc.tasks.save(id, const TasksCompanion(title: Value('Bilgisayar')));

    await pc.sync(); // yeni sürüm önce gider
    await phone.sync(); // eski sürüm reddedilir, yenisi çekilir
    await pc.sync();

    expect((await phone.allTasks()).single.title, 'Bilgisayar');
    expect((await pc.allTasks()).single.title, 'Bilgisayar');
    expect(remote.tables['tasks']![id]!['title'], 'Bilgisayar');
  });

  test('geri kalan saatli cihazda yapılan düzenleme yine de daha yeni sayılır', () async {
    final id = await phone.tasks.create(title: 'Taslak');
    // Sunucudaki sürümün zaman damgası gelecekte (başka cihazın saati ileride).
    final future = DateTime.now().add(const Duration(hours: 1));
    await (phone.db.update(phone.db.tasks)..where((t) => t.id.equals(id)))
        .write(TasksCompanion(updatedAt: Value(future)));
    await phone.sync();
    await pc.sync();

    await pc.tasks.save(id, const TasksCompanion(title: Value('Son hali')));
    await pc.sync();
    await phone.sync();

    expect((await phone.allTasks()).single.title, 'Son hali');
  });

  test('silme işlemi diğer cihaza yayılır', () async {
    final id = await phone.tasks.create(title: 'Silinecek');
    await phone.sync();
    await pc.sync();

    await pc.tasks.delete(id);
    await pc.sync();
    await phone.sync();

    expect((await phone.allTasks()).single.deleted, isTrue);
  });

  test('gönderim sırasında yapılan düzenleme kirli kalır ve sonra gönderilir', () async {
    final id = await phone.tasks.create(title: 'v1');
    remote.duringUpsert = (table) async {
      if (table != 'tasks') return;
      remote.duringUpsert = null;
      await phone.tasks.save(id, const TasksCompanion(title: Value('v2')));
    };
    await phone.sync();
    final local = (await phone.allTasks()).single;
    expect(local.title, 'v2');
    expect(local.dirty, isTrue);

    await phone.sync();
    expect(remote.tables['tasks']![id]!['title'], 'v2');
    expect((await phone.allTasks()).single.dirty, isFalse);
  });

  test('alışkanlık kaydı iki cihazda tek satırda birleşir', () async {
    final habitId = await phone.habits.create(name: 'Su iç', color: 0xFF000000);
    await phone.sync();
    await pc.sync();

    final day = DateTime(2026, 10, 1);
    await phone.habits.setCount(habitId, day, 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pc.habits.setCount(habitId, day, 3);
    await phone.sync();
    await pc.sync();
    await phone.sync();

    final logs = await phone.db.select(phone.db.habitLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.count, 3);
    expect(remote.tables['habit_logs'], hasLength(1));
  });

  test('sayfalama: 500\'den fazla satır eksiksiz aktarılır', () async {
    await phone.db.batch((b) {
      final now = DateTime.now();
      for (var i = 0; i < 1203; i++) {
        b.insert(
          phone.db.tasks,
          TasksCompanion.insert(
              id: 'bulk-$i', title: 'Görev $i', createdAt: now, updatedAt: now),
        );
      }
    });
    await phone.sync();
    expect(remote.upsertCalls, greaterThanOrEqualTo(3));
    await pc.sync();
    expect(await pc.allTasks(), hasLength(1203));
  });
}
