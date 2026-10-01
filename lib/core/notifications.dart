import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Yerel bildirimler: odak zamanlayıcısı ve görev/takvim hatırlatıcıları.
/// Android ve Windows'ta çalışır; diğer platformlarda sessizce hiçbir şey
/// yapmaz.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const timerId = 1;
  static const reminderBaseId = 1000;

  static const _channel = AndroidNotificationDetails(
    'zamanla_reminders',
    'Hatırlatıcılar',
    channelDescription: 'Görev, takvim ve odak zamanlayıcısı bildirimleri',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _details = NotificationDetails(
    android: _channel,
    windows: WindowsNotificationDetails(),
  );

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      await _configureLocalTimezone();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'Zamanla',
            appUserModelId: 'Zamanla.Zamanla.Desktop',
            guid: '6f1d2a4e-3b8c-4d7e-9a51-2c0e8f4b7d13',
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Bildirimler başlatılamadı: $e');
    }
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      return;
    } catch (_) {
      // Bilinmeyen kimlik: mevcut UTC farkına uyan bir konum seç.
    }
    final offset = DateTime.now().timeZoneOffset;
    final match = tz.timeZoneDatabase.locations.values.firstWhere(
      (l) => l.currentTimeZone.offset == offset,
      orElse: () => tz.UTC,
    );
    tz.setLocalLocation(match);
  }

  /// Android 13+ bildirim izni.
  Future<void> requestPermission() async {
    if (!_ready || !Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showNow(int id, String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
        id: id, title: title, body: body, notificationDetails: _details);
  }

  Future<void> schedule(int id, DateTime at, String title, String body) async {
    if (!_ready || !at.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Bildirim zamanlanamadı: $e');
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {
      // zaten yok
    }
  }
}
