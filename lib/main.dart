import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/notifications.dart';
import 'data/database.dart';
import 'data/sync_service.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  Intl.defaultLocale = 'tr';

  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase();

  SupabaseClient? supabase;
  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseKey,
      );
      supabase = Supabase.instance.client;
    } catch (e) {
      debugPrint('Supabase başlatılamadı: $e');
    }
  }

  final notifications = NotificationService();
  await notifications.init();

  final sync = SyncService(db: db, prefs: prefs, client: supabase)..start();

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      prefsProvider.overrideWithValue(prefs),
      syncServiceProvider.overrideWithValue(sync),
      notificationServiceProvider.overrideWithValue(notifications),
    ],
    child: const ZamanlaApp(),
  ));
}
