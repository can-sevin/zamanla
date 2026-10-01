import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../providers.dart';

enum FocusMode { pomodoro, stopwatch }

enum FocusPhase {
  work('Odak'),
  shortBreak('Kısa mola'),
  longBreak('Uzun mola');

  const FocusPhase(this.label);
  final String label;
}

@immutable
class FocusState {
  const FocusState({
    this.mode = FocusMode.pomodoro,
    this.phase = FocusPhase.work,
    this.running = false,
    this.endsAt,
    this.remaining = Duration.zero,
    this.segmentStart,
    this.stopwatchBase = Duration.zero,
    this.completedPomodoros = 0,
    this.taskId,
    this.areaId,
  });

  final FocusMode mode;
  final FocusPhase phase;
  final bool running;

  /// Pomodoro çalışırken bitiş anı (duvar saati; arka planda da doğru kalır).
  final DateTime? endsAt;

  /// Pomodoro duraklatıldığında kalan süre.
  final Duration remaining;

  /// Çalışan bölümün başlangıcı (zaman kaydı için).
  final DateTime? segmentStart;

  /// Kronometrede duraklatmadan önce biriken süre.
  final Duration stopwatchBase;
  final int completedPomodoros;
  final String? taskId;
  final String? areaId;

  Duration remainingAt(DateTime now) => running && endsAt != null
      ? endsAt!.difference(now)
      : remaining;

  Duration elapsedAt(DateTime now) => running && segmentStart != null
      ? stopwatchBase + now.difference(segmentStart!)
      : stopwatchBase;

  FocusState copyWith({
    FocusMode? mode,
    FocusPhase? phase,
    bool? running,
    DateTime? Function()? endsAt,
    Duration? remaining,
    DateTime? Function()? segmentStart,
    Duration? stopwatchBase,
    int? completedPomodoros,
    String? Function()? taskId,
    String? Function()? areaId,
  }) =>
      FocusState(
        mode: mode ?? this.mode,
        phase: phase ?? this.phase,
        running: running ?? this.running,
        endsAt: endsAt != null ? endsAt() : this.endsAt,
        remaining: remaining ?? this.remaining,
        segmentStart: segmentStart != null ? segmentStart() : this.segmentStart,
        stopwatchBase: stopwatchBase ?? this.stopwatchBase,
        completedPomodoros: completedPomodoros ?? this.completedPomodoros,
        taskId: taskId != null ? taskId() : this.taskId,
        areaId: areaId != null ? areaId() : this.areaId,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'phase': phase.name,
        'running': running,
        'endsAt': endsAt?.toIso8601String(),
        'remaining': remaining.inSeconds,
        'segmentStart': segmentStart?.toIso8601String(),
        'stopwatchBase': stopwatchBase.inSeconds,
        'completed': completedPomodoros,
        'taskId': taskId,
        'areaId': areaId,
      };

  static FocusState fromJson(Map<String, dynamic> j) => FocusState(
        mode: FocusMode.values.byName(j['mode'] as String),
        phase: FocusPhase.values.byName(j['phase'] as String),
        running: j['running'] as bool,
        endsAt: j['endsAt'] == null ? null : DateTime.parse(j['endsAt']),
        remaining: Duration(seconds: j['remaining'] as int),
        segmentStart:
            j['segmentStart'] == null ? null : DateTime.parse(j['segmentStart']),
        stopwatchBase: Duration(seconds: j['stopwatchBase'] as int),
        completedPomodoros: j['completed'] as int,
        taskId: j['taskId'] as String?,
        areaId: j['areaId'] as String?,
      );
}

/// Pomodoro ve kronometre. Çalışma bölümleri bittiğinde/durdurulduğunda
/// zaman kaydı (`time_entries`) olarak saklanır. Durum tercihlerde tutulur;
/// uygulama kapanıp açılsa da zamanlayıcı kaldığı yerden devam eder.
class FocusController extends Notifier<FocusState> {
  Timer? _timer;
  static const _prefsKey = 'focus.state';

  /// Bir dakikadan kısa bölümler kaydedilmez.
  static const minEntry = Duration(minutes: 1);

  @override
  FocusState build() {
    ref.onDispose(() => _timer?.cancel());
    final raw = ref.read(prefsProvider).getString(_prefsKey);
    FocusState initial;
    try {
      initial = raw == null
          ? _fresh(FocusPhase.work)
          : FocusState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      initial = _fresh(FocusPhase.work);
    }
    if (initial.running && initial.mode == FocusMode.pomodoro) {
      Future.microtask(() => _armTimer(initial));
    }
    return initial;
  }

  Duration _phaseLength(FocusPhase p) {
    final s = ref.read(settingsProvider);
    return Duration(
      minutes: switch (p) {
        FocusPhase.work => s.pomodoroWork,
        FocusPhase.shortBreak => s.pomodoroShortBreak,
        FocusPhase.longBreak => s.pomodoroLongBreak,
      },
    );
  }

  FocusState _fresh(FocusPhase p) =>
      FocusState(phase: p, remaining: _phaseLength(p));

  NotificationService get _notifications =>
      ref.read(notificationServiceProvider);

  void _set(FocusState s) {
    state = s;
    ref.read(prefsProvider).setString(_prefsKey, jsonEncode(s.toJson()));
  }

  void _armTimer(FocusState s) {
    _timer?.cancel();
    if (!s.running || s.endsAt == null) return;
    final wait = s.endsAt!.difference(DateTime.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _completePhase);
  }

  void setMode(FocusMode mode) {
    if (state.running) return;
    _set(FocusState(
      mode: mode,
      remaining: _phaseLength(FocusPhase.work),
      taskId: state.taskId,
      areaId: state.areaId,
      completedPomodoros: state.completedPomodoros,
    ));
  }

  void selectTask(String? taskId, String? areaId) {
    _set(state.copyWith(taskId: () => taskId, areaId: () => areaId));
  }

  /// Ayarlardaki süreler değişince duran zamanlayıcıyı günceller.
  void refreshDurations() {
    if (!state.running && state.mode == FocusMode.pomodoro) {
      _set(state.copyWith(remaining: _phaseLength(state.phase)));
    }
  }

  Future<void> start() async {
    if (state.running) return;
    final now = DateTime.now();
    await _notifications.requestPermission();
    if (state.mode == FocusMode.stopwatch) {
      _set(state.copyWith(running: true, segmentStart: () => now));
      return;
    }
    final remaining = state.remaining <= Duration.zero
        ? _phaseLength(state.phase)
        : state.remaining;
    final next = state.copyWith(
      running: true,
      endsAt: () => now.add(remaining),
      segmentStart: () => now,
    );
    _set(next);
    _armTimer(next);
    await _notifications.schedule(
      NotificationService.timerId,
      next.endsAt!,
      state.phase == FocusPhase.work ? 'Odak süresi bitti 🎉' : 'Mola bitti',
      state.phase == FocusPhase.work
          ? 'Kısa bir mola verme zamanı.'
          : 'Yeni bir odak oturumuna hazır mısın?',
    );
  }

  Future<void> pause() async {
    if (!state.running) return;
    _timer?.cancel();
    await _notifications.cancel(NotificationService.timerId);
    final now = DateTime.now();
    if (state.mode == FocusMode.stopwatch) {
      await _recordSegment(now, 'stopwatch');
      _set(state.copyWith(
        running: false,
        stopwatchBase: state.elapsedAt(now),
        segmentStart: () => null,
      ));
      return;
    }
    if (state.phase == FocusPhase.work) await _recordSegment(now, 'pomodoro');
    _set(state.copyWith(
      running: false,
      remaining: state.remainingAt(now),
      endsAt: () => null,
      segmentStart: () => null,
    ));
  }

  /// Zamanlayıcıyı sıfırlar (çalışan bölüm kaydedilir).
  Future<void> reset() async {
    if (state.running) await pause();
    if (state.mode == FocusMode.stopwatch) {
      _set(state.copyWith(stopwatchBase: Duration.zero));
    } else {
      _set(state.copyWith(remaining: _phaseLength(state.phase)));
    }
  }

  /// Mevcut aşamayı atlayıp bir sonrakine geçer.
  Future<void> skip() async {
    if (state.mode != FocusMode.pomodoro) return;
    if (state.running) await pause();
    _advance(countPomodoro: false);
  }

  Future<void> _completePhase() async {
    if (!state.running) return;
    final now = DateTime.now();
    final wasWork = state.phase == FocusPhase.work;
    if (wasWork) {
      await _recordSegment(state.endsAt ?? now, 'pomodoro');
    }
    // Uygulama açıkken bildirimi hemen göster (zamanlanan zaten düşebilir).
    await _notifications.cancel(NotificationService.timerId);
    await _notifications.showNow(
      NotificationService.timerId,
      wasWork ? 'Odak süresi bitti 🎉' : 'Mola bitti',
      wasWork
          ? 'Kısa bir mola verme zamanı.'
          : 'Yeni bir odak oturumuna hazır mısın?',
    );
    _set(state.copyWith(
        running: false, endsAt: () => null, segmentStart: () => null));
    _advance(countPomodoro: wasWork);
  }

  void _advance({required bool countPomodoro}) {
    final s = ref.read(settingsProvider);
    var completed = state.completedPomodoros + (countPomodoro ? 1 : 0);
    final FocusPhase next;
    if (state.phase == FocusPhase.work) {
      next = countPomodoro && completed % s.pomodoroLongEvery == 0
          ? FocusPhase.longBreak
          : FocusPhase.shortBreak;
    } else {
      next = FocusPhase.work;
    }
    _set(state.copyWith(
      phase: next,
      remaining: _phaseLength(next),
      completedPomodoros: completed,
      running: false,
      endsAt: () => null,
      segmentStart: () => null,
    ));
  }

  Future<void> _recordSegment(DateTime end, String kind) async {
    final start = state.segmentStart;
    if (start == null || end.difference(start) < minEntry) return;
    await ref.read(timeEntriesRepoProvider).add(
          startAt: start,
          endAt: end,
          taskId: state.taskId,
          areaId: state.areaId,
          kind: kind,
        );
  }
}
