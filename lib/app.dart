import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/sync_service.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_shell.dart';
import 'providers.dart';

class ZamanlaApp extends ConsumerStatefulWidget {
  const ZamanlaApp({super.key});

  @override
  ConsumerState<ZamanlaApp> createState() => _ZamanlaAppState();
}

class _ZamanlaAppState extends ConsumerState<ZamanlaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider).schedule(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    // Hatırlatıcı zamanlayıcısını canlı tut.
    ref.watch(reminderSchedulerProvider);

    return MaterialApp(
      title: 'Zamanla',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _AuthGate(),
    );
  }
}

/// Supabase yapılandırılmış, oturum açılmamış ve kullanıcı "hesapsız devam"
/// seçmemişse giriş ekranını gösterir.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ??
        ref.read(syncServiceProvider).status;
    final skipped = ref.watch(settingsProvider.select((s) => s.authSkipped));
    if (status.phase == SyncPhase.signedOut && !skipped) {
      return const AuthScreen(showSkip: true);
    }
    return const HomeShell();
  }
}
