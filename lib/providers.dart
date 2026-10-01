import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_client.dart';
import 'ai/ai_service.dart';
import 'ai/providers.dart';
import 'core/dates.dart';
import 'core/notifications.dart';
import 'core/settings.dart';
import 'data/database.dart';
import 'data/repositories.dart';
import 'data/sync_service.dart';
import 'features/focus/focus_controller.dart';

// ---------------------------------------------------------------------------
// main() içinde override edilen temel servisler
// ---------------------------------------------------------------------------

final databaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError());
final prefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());
final syncServiceProvider =
    Provider<SyncService>((ref) => throw UnimplementedError());
final notificationServiceProvider =
    Provider<NotificationService>((ref) => throw UnimplementedError());

// ---------------------------------------------------------------------------
// Depolar
// ---------------------------------------------------------------------------

final areasRepoProvider =
    Provider((ref) => AreasRepository(ref.watch(databaseProvider)));
final tasksRepoProvider =
    Provider((ref) => TasksRepository(ref.watch(databaseProvider)));
final blocksRepoProvider =
    Provider((ref) => BlocksRepository(ref.watch(databaseProvider)));
final timeEntriesRepoProvider =
    Provider((ref) => TimeEntriesRepository(ref.watch(databaseProvider)));
final habitsRepoProvider =
    Provider((ref) => HabitsRepository(ref.watch(databaseProvider)));
final goalsRepoProvider =
    Provider((ref) => GoalsRepository(ref.watch(databaseProvider)));

// ---------------------------------------------------------------------------
// Ayarlar
// ---------------------------------------------------------------------------

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(prefsProvider));

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await state.save(ref.read(prefsProvider));
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------------------------------------------------------------------
// Alan filtresi (Tümü / İş / Kişisel / …) — tüm ekranlarda ortak
// ---------------------------------------------------------------------------

class AreaFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? areaId) => state = areaId;
}

final areaFilterProvider =
    NotifierProvider<AreaFilterNotifier, String?>(AreaFilterNotifier.new);

bool matchesArea(String? filter, String? areaId) =>
    filter == null || filter == areaId;

// ---------------------------------------------------------------------------
// Veri akışları
// ---------------------------------------------------------------------------

final areasProvider = StreamProvider<List<Area>>(
    (ref) => ref.watch(areasRepoProvider).watchAll());

final areaMapProvider = Provider<Map<String, Area>>((ref) => {
      for (final a in ref.watch(areasProvider).value ?? const <Area>[]) a.id: a,
    });

final openTasksProvider = StreamProvider<List<Task>>(
    (ref) => ref.watch(tasksRepoProvider).watchTopLevel());

final filteredOpenTasksProvider = Provider<AsyncValue<List<Task>>>((ref) {
  final filter = ref.watch(areaFilterProvider);
  return ref.watch(openTasksProvider).whenData(
      (list) => [for (final t in list) if (matchesArea(filter, t.areaId)) t]);
});

final completedRecentlyProvider = StreamProvider<List<Task>>((ref) => ref
    .watch(tasksRepoProvider)
    .watchCompletedSince(DateTime.now().subtract(const Duration(days: 30))));

final subtaskCountsProvider = StreamProvider<Map<String, (int, int)>>(
    (ref) => ref.watch(tasksRepoProvider).watchSubtaskCounts());

final taskProvider = StreamProvider.autoDispose.family<Task?, String>(
    (ref, id) => ref.watch(tasksRepoProvider).watchOne(id));

final subtasksProvider = StreamProvider.autoDispose.family<List<Task>, String>(
    (ref, id) => ref.watch(tasksRepoProvider).watchSubtasks(id));

final tasksByGoalProvider = StreamProvider.autoDispose
    .family<List<Task>, String>(
        (ref, id) => ref.watch(tasksRepoProvider).watchByGoal(id));

/// Anahtar: (başlangıç, bitiş) — her ikisi de gün başlangıcına yuvarlanmış.
final blocksInRangeProvider = StreamProvider.autoDispose
    .family<List<TimeBlock>, (DateTime, DateTime)>(
        (ref, r) => ref.watch(blocksRepoProvider).watchRange(r.$1, r.$2));

final entriesInRangeProvider = StreamProvider.autoDispose
    .family<List<TimeEntry>, (DateTime, DateTime)>(
        (ref, r) => ref.watch(timeEntriesRepoProvider).watchRange(r.$1, r.$2));

final habitsProvider = StreamProvider<List<Habit>>(
    (ref) => ref.watch(habitsRepoProvider).watchAll());

/// Anahtar: (ilk gün, son gün) dahil.
final habitLogsProvider = StreamProvider.autoDispose
    .family<Map<String, int>, (DateTime, DateTime)>(
        (ref, r) => ref.watch(habitsRepoProvider).watchLogs(r.$1, r.$2));

final goalsProvider = StreamProvider<List<Goal>>(
    (ref) => ref.watch(goalsRepoProvider).watchAll());

final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final service = ref.watch(syncServiceProvider);
  yield service.status;
  yield* service.statusStream;
});

/// Her dakika yenilenen "şimdi" (takvimdeki şimdi çizgisi, gün değişimi).
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

final todayProvider = Provider<DateTime>((ref) =>
    startOfDay(ref.watch(clockProvider).value ?? DateTime.now()));

// ---------------------------------------------------------------------------
// Odak zamanlayıcısı
// ---------------------------------------------------------------------------

final focusProvider =
    NotifierProvider<FocusController, FocusState>(FocusController.new);

// ---------------------------------------------------------------------------
// Yapay zeka
// ---------------------------------------------------------------------------

const secureStorage = FlutterSecureStorage();

String aiKeyStorageKey(AiProviderKind kind) => 'ai.key.${kind.name}';

final aiKeyProvider = FutureProvider.family<String, AiProviderKind>(
    (ref, kind) async =>
        await secureStorage.read(key: aiKeyStorageKey(kind)) ?? '');

/// Yapılandırılmamışsa null döner.
final aiServiceProvider = FutureProvider<AiService?>((ref) async {
  final s = ref.watch(settingsProvider);
  final key = await ref.watch(aiKeyProvider(s.aiProvider).future);
  if (key.isEmpty && !s.aiProvider.apiKeyOptional) return null;
  if (s.aiProvider.needsBaseUrl && s.aiBaseUrl.trim().isEmpty) return null;
  return AiService(createAiClient(
    kind: s.aiProvider,
    model: s.effectiveAiModel,
    apiKey: key,
    baseUrl: s.aiBaseUrl,
  ));
});

// ---------------------------------------------------------------------------
// Hatırlatıcılar
// ---------------------------------------------------------------------------

/// Önümüzdeki 7 gündeki takvim bloklarını ve saatli görevleri yerel
/// bildirim olarak zamanlar. Veriler değiştikçe yeniden hesaplar.
final reminderSchedulerProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final settings = ref.watch(settingsProvider);
  final prefs = ref.watch(prefsProvider);
  if (!notifications.supported) return;

  Timer? debounce;
  Future<void> reschedule() async {
    const maxReminders = 40;
    final previous = prefs.getInt('reminders.count') ?? maxReminders;
    for (var i = 0; i < previous; i++) {
      await notifications.cancel(NotificationService.reminderBaseId + i);
    }
    if (!settings.remindersEnabled) {
      await prefs.setInt('reminders.count', 0);
      return;
    }
    final now = DateTime.now();
    final until = now.add(const Duration(days: 7));
    final lead = Duration(minutes: settings.reminderLeadMinutes);
    final items = <(DateTime, String, String)>[];

    final blocks =
        await BlocksRepository(db).getRange(now, until.add(lead));
    for (final b in blocks) {
      if (b.kind == 'break') continue;
      final at = b.startAt.subtract(lead);
      if (at.isAfter(now)) {
        items.add((at, b.title, '${formatTime(b.startAt)} – ${formatTime(b.endAt)}'));
      }
    }
    final tasks = await (db.select(db.tasks)
          ..where((t) =>
              t.deleted.equals(false) &
              t.status.equals('todo') &
              t.dueHasTime.equals(true) &
              t.dueAt.isBetweenValues(now, until)))
        .get();
    for (final t in tasks) {
      items.add((t.dueAt!, t.title, 'Son tarih: ${formatTime(t.dueAt!)}'));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    final selected = items.take(maxReminders).toList();
    for (var i = 0; i < selected.length; i++) {
      final (at, title, body) = selected[i];
      await notifications.schedule(
          NotificationService.reminderBaseId + i, at, title, body);
    }
    await prefs.setInt('reminders.count', selected.length);
  }

  void trigger() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 3), reschedule);
  }

  final sub = db
      .tableUpdates(TableUpdateQuery.onAllTables([db.blocks, db.tasks]))
      .listen((_) => trigger());
  trigger();
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
  });
});
