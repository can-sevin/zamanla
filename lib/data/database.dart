import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Senkronize edilen her tablonun ortak sütunları.
///
/// `updated_at` son yerel değişiklik zamanıdır ve çakışmalarda
/// "son yazan kazanır" kuralı için kullanılır. `dirty` yalnızca yereldir:
/// sunucuya henüz gönderilmemiş değişiklikleri işaretler.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Yaşam alanları: İş, Kişisel ve kullanıcının eklediği diğerleri.
@DataClassName('Area')
class Areas extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get color => integer()();
  TextColumn get icon => text().withDefault(const Constant(''))();

  /// work | personal | other
  TextColumn get kind => text().withDefault(const Constant('other'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('Goal')
class Goals extends Table with SyncColumns {
  TextColumn get areaId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get targetDate => dateTime().nullable()();

  /// tasks: bağlı görevlerin tamamlanma oranı; manual: current/target.
  TextColumn get progressMode => text().withDefault(const Constant('tasks'))();
  RealColumn get targetValue => real().withDefault(const Constant(100))();
  RealColumn get currentValue => real().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant(''))();

  /// active | done | archived
  TextColumn get status => text().withDefault(const Constant('active'))();
}

@DataClassName('Task')
class Tasks extends Table with SyncColumns {
  TextColumn get areaId => text().nullable()();
  TextColumn get goalId => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// 0 yok, 1 düşük, 2 orta, 3 yüksek
  IntColumn get priority => integer().withDefault(const Constant(0))();
  BoolColumn get important => boolean().withDefault(const Constant(false))();
  BoolColumn get urgent => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  BoolColumn get dueHasTime => boolean().withDefault(const Constant(false))();
  IntColumn get estimateMinutes => integer().nullable()();

  /// todo | done
  TextColumn get status => text().withDefault(const Constant('todo'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// null | daily | weekdays | weekly | monthly
  TextColumn get recurrence => text().nullable()();
}

/// Takvimdeki zaman blokları (toplantı, odak bloğu, göreve ayrılan süre).
@DataClassName('TimeBlock')
class Blocks extends Table with SyncColumns {
  TextColumn get areaId => text().nullable()();
  TextColumn get taskId => text().nullable()();
  TextColumn get title => text()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get color => integer().nullable()();

  /// task | event | focus | break
  TextColumn get kind => text().withDefault(const Constant('event'))();
}

/// Gerçekte harcanan süre kayıtları (pomodoro, kronometre, elle).
@DataClassName('TimeEntry')
class TimeEntries extends Table with SyncColumns {
  TextColumn get taskId => text().nullable()();
  TextColumn get areaId => text().nullable()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime().nullable()();

  /// pomodoro | stopwatch | manual
  TextColumn get kind => text().withDefault(const Constant('manual'))();
  TextColumn get note => text().withDefault(const Constant(''))();
}

@DataClassName('Habit')
class Habits extends Table with SyncColumns {
  TextColumn get areaId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant(''))();
  IntColumn get color => integer()();
  IntColumn get targetPerDay => integer().withDefault(const Constant(1))();

  /// Bit maskesi: bit 0 = Pazartesi … bit 6 = Pazar. 127 = her gün.
  IntColumn get weekdays => integer().withDefault(const Constant(127))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Bir alışkanlığın bir gündeki tamamlanma sayısı. id deterministiktir
/// (`habitId_yyyy-MM-dd`), böylece iki cihaz aynı gün için tek satırda birleşir.
@DataClassName('HabitLog')
class HabitLogs extends Table with SyncColumns {
  TextColumn get habitId => text()();
  TextColumn get day => text()();
  IntColumn get count => integer().withDefault(const Constant(0))();
}

/// Varsayılan alanların sabit kimlikleri. Tüm cihazlarda aynı olduklarından
/// senkronizasyonda çoğalmazlar.
const workAreaId = 'area-work';
const personalAreaId = 'area-personal';

/// Varsayılan kayıtların zaman damgası: kullanıcının her gerçek düzenlemesi
/// bundan yeni olduğu için, yeni kurulan bir cihaz eski düzenlemeleri ezmez.
final seedTimestamp = DateTime.utc(2020);

@DriftDatabase(
  tables: [Areas, Goals, Tasks, Blocks, TimeEntries, Habits, HabitLogs],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'zamanla'));

  /// Kullanıcı kaynaklı her yazmadan sonra çağrılır (senkronizasyonu tetikler).
  void Function()? onLocalWrite;

  void notifyLocalWrite() => onLocalWrite?.call();

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedDefaults();
        },
      );

  Future<void> seedDefaults() async {
    await batch((b) {
      b.insertAll(
        areas,
        [
          AreasCompanion.insert(
            id: workAreaId,
            name: 'İş',
            color: 0xFF3F6FD8,
            icon: const Value('💼'),
            kind: const Value('work'),
            sortOrder: const Value(0),
            createdAt: seedTimestamp,
            updatedAt: seedTimestamp,
          ),
          AreasCompanion.insert(
            id: personalAreaId,
            name: 'Kişisel',
            color: 0xFF2E9D6A,
            icon: const Value('🏡'),
            kind: const Value('personal'),
            sortOrder: const Value(1),
            createdAt: seedTimestamp,
            updatedAt: seedTimestamp,
          ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Oturum kapatılırken bu cihazdaki tüm kullanıcı verisini siler.
  Future<void> wipeAll() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
      await seedDefaults();
    });
  }
}
