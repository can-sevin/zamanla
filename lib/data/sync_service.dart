import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';

enum SyncPhase { disabled, signedOut, idle, syncing, error }

@immutable
class SyncStatus {
  const SyncStatus(this.phase, {this.lastSyncedAt, this.error});

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? error;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncedAt, String? error}) =>
      SyncStatus(phase ?? this.phase,
          lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt, error: error);
}

/// drift satırlarını Supabase JSON'una çevirir ve geri okur.
/// Tarihler UTC ISO-8601 olarak gönderilir, yerel saate çevrilerek okunur.
class SyncSerializer extends ValueSerializer {
  const SyncSerializer();

  @override
  T fromJson<T>(dynamic json) {
    if (json == null) return null as T;
    final probe = <T>[];
    if (probe is List<DateTime?>) {
      return DateTime.parse(json as String).toLocal() as T;
    }
    if (probe is List<double?>) return (json as num).toDouble() as T;
    if (probe is List<int?>) return (json as num).toInt() as T;
    return json as T;
  }

  @override
  dynamic toJson<T>(T value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value;
  }
}

const syncSerializer = SyncSerializer();

/// Bir tablonun senkronizasyon tanımı.
class SyncTable {
  SyncTable(this.table, this.fromJson);

  final TableInfo<Table, DataClass> table;
  final Insertable<DataClass> Function(Map<String, dynamic> json) fromJson;

  String get name => table.actualTableName;
}

List<SyncTable> syncTablesOf(AppDatabase db) => [
      SyncTable(db.areas, (j) => Area.fromJson(j, serializer: syncSerializer)),
      SyncTable(db.goals, (j) => Goal.fromJson(j, serializer: syncSerializer)),
      SyncTable(db.tasks, (j) => Task.fromJson(j, serializer: syncSerializer)),
      SyncTable(
          db.blocks, (j) => TimeBlock.fromJson(j, serializer: syncSerializer)),
      SyncTable(db.timeEntries,
          (j) => TimeEntry.fromJson(j, serializer: syncSerializer)),
      SyncTable(db.habits, (j) => Habit.fromJson(j, serializer: syncSerializer)),
      SyncTable(
          db.habitLogs, (j) => HabitLog.fromJson(j, serializer: syncSerializer)),
    ];

/// Çekme imleçlerinin saklandığı yer (testlerde bellek içi).
abstract class CursorStore {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class PrefsCursorStore implements CursorStore {
  PrefsCursorStore(this.prefs);
  final SharedPreferences prefs;

  @override
  String? read(String key) => prefs.getString(key);

  @override
  Future<void> write(String key, String value) => prefs.setString(key, value);

  @override
  Future<void> remove(String key) => prefs.remove(key);
}

/// Uzak sunucu soyutlaması (testlerde sahte uygulama kullanılır).
abstract class SyncRemote {
  /// Satırları yazar ve sunucunun kabul ettiği satırların kimliklerini
  /// döndürür. Sunucudaki sürüm daha yeniyse satır reddedilir.
  Future<Set<String>> upsert(String table, List<Map<String, dynamic>> rows);

  Future<List<Map<String, dynamic>>> fetchByIds(String table, List<String> ids);

  /// `server_updated_at > after` olan satırlar, artan sırada.
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, DateTime after, int limit);
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this.client);
  final SupabaseClient client;

  @override
  Future<Set<String>> upsert(String table, List<Map<String, dynamic>> rows) async {
    final stored = await client
        .from(table)
        .upsert(rows, onConflict: 'user_id,id')
        .select('id');
    return {for (final r in stored) r['id'] as String};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchByIds(
          String table, List<String> ids) =>
      client.from(table).select().inFilter('id', ids);

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, DateTime after, int limit) {
    return client
        .from(table)
        .select()
        .gt('server_updated_at', after.toUtc().toIso8601String())
        .order('server_updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
  }
}

/// Yerel veritabanı ile Supabase arasında çift yönlü senkronizasyon.
///
/// * Gönder: `dirty` satırlar `upsert` edilir; gönderim sırasında
///   değişmeyenlerin işareti kaldırılır.
/// * Çek: her tablo için `server_updated_at` imlecinden sonraki satırlar
///   alınır. Yerelde daha yeni ve gönderilmemiş bir sürüm varsa korunur.
///   Gecikmeli işlenen sunucu işlemlerini kaçırmamak için imleç küçük bir
///   örtüşme payıyla geri alınır (uygulama idempotenttir).
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.remote,
    required this.userId,
    required this.cursors,
  }) : tables = syncTablesOf(db);

  final AppDatabase db;
  final SyncRemote remote;
  final String userId;
  final CursorStore cursors;
  final List<SyncTable> tables;

  static const pageSize = 500;
  static const overlap = Duration(minutes: 2);

  String _cursorKey(String table) => 'sync.cursor.$userId.$table';

  Future<void> run() async {
    for (final t in tables) {
      await _push(t);
    }
    for (final t in tables) {
      await _pull(t);
    }
  }

  Future<void> _push(SyncTable t) async {
    while (true) {
      final rows = await db
          .customSelect(
            'SELECT * FROM ${t.name} WHERE dirty = 1 LIMIT $pageSize',
            readsFrom: {t.table},
          )
          .get();
      if (rows.isEmpty) return;

      final pushed = <String, Map<String, dynamic>>{};
      final payload = <Map<String, dynamic>>[];
      for (final row in rows) {
        final data = await t.table.map(row.data);
        final json = data.toJson(serializer: syncSerializer);
        pushed[json['id'] as String] = json;
        payload.add(Map.of(json)
          ..remove('dirty')
          ..['user_id'] = userId);
      }
      final accepted = await remote.upsert(t.name, payload);

      // Gönderim sürerken düzenlenen satırlar kirli kalmalı.
      await db.transaction(() async {
        for (final entry in pushed.entries) {
          final current = await db
              .customSelect('SELECT * FROM ${t.name} WHERE id = ?',
                  variables: [Variable.withString(entry.key)],
                  readsFrom: {t.table})
              .getSingleOrNull();
          if (current == null) continue;
          final now = (await t.table.map(current.data))
              .toJson(serializer: syncSerializer);
          if (mapEquals(now, entry.value)) {
            await db.customUpdate(
              'UPDATE ${t.name} SET dirty = 0 WHERE id = ?',
              variables: [Variable.withString(entry.key)],
            );
          }
        }
      });

      // Reddedilenlerin sunucuda daha yeni bir sürümü var: onu al.
      final rejected =
          pushed.keys.where((id) => !accepted.contains(id)).toList();
      if (rejected.isNotEmpty) {
        final newer = await remote.fetchByIds(t.name, rejected);
        await db.transaction(() async {
          for (final row in newer) {
            await _apply(t, row);
          }
        });
      }
      if (rows.length < pageSize) return;
    }
  }

  Future<void> _pull(SyncTable t) async {
    final key = _cursorKey(t.name);
    final saved = cursors.read(key);
    var cursor = saved == null
        ? DateTime.utc(1970)
        : DateTime.parse(saved).subtract(overlap);
    DateTime? maxSeen = saved == null ? null : DateTime.parse(saved);

    while (true) {
      final rows = await remote.fetchChanges(t.name, cursor, pageSize);
      if (rows.isEmpty) break;
      await db.transaction(() async {
        for (final remoteRow in rows) {
          await _apply(t, remoteRow);
        }
      });
      final last = DateTime.parse(rows.last['server_updated_at'] as String);
      cursor = last;
      if (maxSeen == null || last.isAfter(maxSeen)) maxSeen = last;
      if (rows.length < pageSize) break;
    }
    if (maxSeen != null) {
      await cursors.write(key, maxSeen.toUtc().toIso8601String());
    }
  }

  Future<void> _apply(SyncTable t, Map<String, dynamic> remoteRow) async {
    final id = remoteRow['id'] as String;
    final local = await db
        .customSelect('SELECT * FROM ${t.name} WHERE id = ?',
            variables: [Variable.withString(id)], readsFrom: {t.table})
        .getSingleOrNull();
    final remoteUpdated = DateTime.parse(remoteRow['updated_at'] as String);
    if (local != null) {
      final localJson =
          (await t.table.map(local.data)).toJson(serializer: syncSerializer);
      final localUpdated = DateTime.parse(localJson['updated_at'] as String);
      final localDirty = localJson['dirty'] == true;
      // Gönderilmemiş yerel değişiklik aynı veya daha yeniyse korunur;
      // bir sonraki gönderimde sunucu da bu sürümü kabul eder.
      if (localDirty && !remoteUpdated.isAfter(localUpdated)) return;
      if (!localDirty && remoteUpdated.isBefore(localUpdated)) return;
    }
    final json = Map<String, dynamic>.of(remoteRow)..['dirty'] = false;
    await db.into(t.table).insertOnConflictUpdate(t.fromJson(json));
  }

  Future<void> clearCursors() async {
    for (final t in tables) {
      await cursors.remove(_cursorKey(t.name));
    }
  }

  Future<int> pendingCount() async {
    var total = 0;
    for (final t in tables) {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM ${t.name} WHERE dirty = 1')
          .getSingle();
      total += row.read<int>('c');
    }
    return total;
  }
}

/// Oturum durumuna göre senkronizasyonu zamanlayan servis: açılışta,
/// yerel yazmalardan kısa süre sonra, periyodik olarak ve başka bir
/// cihazdan realtime bildirimi geldiğinde çalışır.
class SyncService {
  SyncService({required this.db, required this.prefs, this.client}) {
    db.onLocalWrite = () => schedule(const Duration(seconds: 2));
  }

  final AppDatabase db;
  final SharedPreferences prefs;
  final SupabaseClient? client;

  final _status = StreamController<SyncStatus>.broadcast();
  SyncStatus _current = const SyncStatus(SyncPhase.disabled);
  Timer? _debounce;
  Timer? _periodic;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  bool _running = false;
  bool _again = false;

  Stream<SyncStatus> get statusStream => _status.stream;
  SyncStatus get status => _current;

  String? get userId => client?.auth.currentUser?.id;

  void _emit(SyncStatus s) {
    _current = s;
    _status.add(s);
  }

  void start() {
    final c = client;
    if (c == null) {
      _emit(const SyncStatus(SyncPhase.disabled));
      return;
    }
    final last = prefs.getString('sync.lastSyncedAt');
    _current = SyncStatus(
      c.auth.currentUser == null ? SyncPhase.signedOut : SyncPhase.idle,
      lastSyncedAt: last == null ? null : DateTime.parse(last).toLocal(),
    );
    _emit(_current);
    _authSub = c.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession) {
        if (state.session != null) _onSignedIn();
      } else if (state.event == AuthChangeEvent.signedOut) {
        _onSignedOut();
      }
    });
    if (c.auth.currentUser != null) _onSignedIn();
  }

  void _onSignedIn() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    _subscribeRealtime();
    if (_current.phase == SyncPhase.signedOut ||
        _current.phase == SyncPhase.disabled) {
      _emit(_current.copyWith(phase: SyncPhase.idle));
    }
    syncNow();
  }

  void _onSignedOut() {
    _periodic?.cancel();
    _debounce?.cancel();
    _unsubscribeRealtime();
    _emit(const SyncStatus(SyncPhase.signedOut));
  }

  void _subscribeRealtime() {
    final c = client;
    if (c == null || _channel != null) return;
    var channel = c.channel('zamanla-sync');
    for (final t in syncTablesOf(db)) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t.name,
        callback: (_) => schedule(const Duration(seconds: 1)),
      );
    }
    _channel = channel..subscribe();
  }

  void _unsubscribeRealtime() {
    final ch = _channel;
    _channel = null;
    if (ch != null) client?.removeChannel(ch);
  }

  /// Uygulama ön plana döndüğünde vb. çağrılır.
  void schedule([Duration delay = const Duration(seconds: 2)]) {
    if (userId == null) return;
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    final c = client;
    final uid = userId;
    if (c == null || uid == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _emit(_current.copyWith(phase: SyncPhase.syncing));
    try {
      do {
        _again = false;
        await SyncEngine(
          db: db,
          remote: SupabaseSyncRemote(c),
          userId: uid,
          cursors: PrefsCursorStore(prefs),
        ).run();
      } while (_again);
      final now = DateTime.now();
      await prefs.setString('sync.lastSyncedAt', now.toUtc().toIso8601String());
      _emit(SyncStatus(SyncPhase.idle, lastSyncedAt: now));
    } catch (e, st) {
      debugPrint('Senkronizasyon hatası: $e\n$st');
      _emit(_current.copyWith(phase: SyncPhase.error, error: _describe(e)));
    } finally {
      _running = false;
    }
  }

  String _describe(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42P01' || e.code == 'PGRST205') {
        return 'Supabase tabloları bulunamadı. supabase/schema.sql dosyasını '
            'SQL Editor\'de çalıştırın.';
      }
      return e.message;
    }
    if (e is AuthException) return e.message;
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.';
    }
    return text;
  }

  Future<int> pendingCount() async {
    final uid = userId ?? '';
    return SyncEngine(
      db: db,
      remote: SupabaseSyncRemote(client!),
      userId: uid,
      cursors: PrefsCursorStore(prefs),
    ).pendingCount();
  }

  /// Oturumu kapatır ve bu cihazdaki verileri siler (başka bir hesabın
  /// verisiyle karışmaması için). Önce son bir senkronizasyon dener.
  Future<void> signOutAndWipe() async {
    final c = client;
    final uid = userId;
    if (c == null) return;
    await syncNow();
    if (uid != null) {
      await SyncEngine(
        db: db,
        remote: SupabaseSyncRemote(c),
        userId: uid,
        cursors: PrefsCursorStore(prefs),
      ).clearCursors();
    }
    await c.auth.signOut();
    await db.wipeAll();
    await prefs.remove('sync.lastSyncedAt');
  }

  void dispose() {
    _authSub?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    _unsubscribeRealtime();
    _status.close();
  }
}
