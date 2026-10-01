import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/sync_service.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../auth/auth_screen.dart';
import 'ai_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    String minutesLabel(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

    Future<void> pickWorkTime(bool start) async {
      final current = start ? s.workStart : s.workEnd;
      final t = await pickTime(context, current);
      if (t == null) return;
      final m = t.hour * 60 + t.minute;
      await notifier.update((x) => start
          ? x.copyWith(workStartMinutes: m)
          : x.copyWith(workEndMinutes: m));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
          children: [
            const _SyncSection(),
            const SectionHeader('Görünüm'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('Sistem')),
                  ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('Açık')),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('Koyu')),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) =>
                    notifier.update((x) => x.copyWith(themeMode: v.first)),
              ),
            ),
            const SectionHeader('Alanlar'),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('İş, Kişisel ve diğer alanlar'),
              subtitle: const Text('Ekle, yeniden adlandır, renk değiştir'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => const AreasScreen())),
            ),
            const SectionHeader('Çalışma saatleri'),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: const Text('Gün başlangıcı'),
              subtitle: const Text('Yapay zeka planlaması ve takvim vurgusu için'),
              trailing: Text(minutesLabel(s.workStartMinutes)),
              onTap: () => pickWorkTime(true),
            ),
            ListTile(
              leading: const Icon(Icons.nights_stay_outlined),
              title: const Text('Gün sonu'),
              trailing: Text(minutesLabel(s.workEndMinutes)),
              onTap: () => pickWorkTime(false),
            ),
            const SectionHeader('Odak zamanlayıcısı'),
            _Stepper(
              icon: Icons.timer_outlined,
              label: 'Odak süresi',
              value: s.pomodoroWork,
              suffix: 'dk',
              min: 5,
              max: 120,
              step: 5,
              onChanged: (v) async {
                await notifier.update((x) => x.copyWith(pomodoroWork: v));
                ref.read(focusProvider.notifier).refreshDurations();
              },
            ),
            _Stepper(
              icon: Icons.coffee_outlined,
              label: 'Kısa mola',
              value: s.pomodoroShortBreak,
              suffix: 'dk',
              min: 1,
              max: 30,
              onChanged: (v) async {
                await notifier.update((x) => x.copyWith(pomodoroShortBreak: v));
                ref.read(focusProvider.notifier).refreshDurations();
              },
            ),
            _Stepper(
              icon: Icons.weekend_outlined,
              label: 'Uzun mola',
              value: s.pomodoroLongBreak,
              suffix: 'dk',
              min: 5,
              max: 60,
              step: 5,
              onChanged: (v) async {
                await notifier.update((x) => x.copyWith(pomodoroLongBreak: v));
                ref.read(focusProvider.notifier).refreshDurations();
              },
            ),
            _Stepper(
              icon: Icons.repeat,
              label: 'Uzun mola sıklığı',
              value: s.pomodoroLongEvery,
              suffix: 'pomodoroda bir',
              min: 2,
              max: 8,
              onChanged: (v) =>
                  notifier.update((x) => x.copyWith(pomodoroLongEvery: v)),
            ),
            const SectionHeader('Hatırlatıcılar'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Takvim ve görev hatırlatıcıları'),
              subtitle: const Text('Önümüzdeki 7 gün için bildirim zamanlanır'),
              value: s.remindersEnabled,
              onChanged: (v) async {
                if (v) await ref.read(notificationServiceProvider).requestPermission();
                await notifier.update((x) => x.copyWith(remindersEnabled: v));
              },
            ),
            _Stepper(
              icon: Icons.alarm,
              label: 'Etkinlikten önce',
              value: s.reminderLeadMinutes,
              suffix: 'dk',
              min: 0,
              max: 60,
              step: 5,
              onChanged: (v) =>
                  notifier.update((x) => x.copyWith(reminderLeadMinutes: v)),
            ),
            const SectionHeader('Yapay zeka'),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Sağlayıcı ve API anahtarı'),
              subtitle: Text('${s.aiProvider.label} · ${s.effectiveAiModel}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen())),
            ),
            const SectionHeader('Hakkında'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Zamanla'),
              subtitle: Text(
                  'Kısayollar (Windows): Ctrl+N yeni görev · Ctrl+K hızlı ekle · Ctrl+1…9 ekranlar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.icon,
    required this.label,
    required this.value,
    required this.suffix,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final IconData icon;
  final String label;
  final int value;
  final String suffix;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value - step >= min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('$value $suffix'),
          IconButton(
            onPressed: value + step <= max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.read(syncServiceProvider);
    final status = ref.watch(syncStatusProvider).value ?? service.status;
    final email = service.client?.auth.currentUser?.email;
    final last = status.lastSyncedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Hesap ve senkronizasyon'),
        switch (status.phase) {
          SyncPhase.disabled => const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Yalnızca bu cihaz'),
              subtitle: Text(
                  'Supabase yapılandırılmadığı için veriler yalnızca bu cihazda tutuluyor. '
                  'Kurulum için README dosyasına bakın.'),
            ),
          SyncPhase.signedOut => ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Giriş yapılmadı'),
              subtitle: const Text(
                  'Telefon ve bilgisayar arasında eşitlemek için giriş yap.'),
              trailing: FilledButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const AuthScreen(showSkip: false))),
                child: const Text('Giriş yap'),
              ),
            ),
          _ => Column(
              children: [
                ListTile(
                  leading: Icon(
                    status.phase == SyncPhase.error
                        ? Icons.sync_problem
                        : Icons.cloud_done_outlined,
                    color: status.phase == SyncPhase.error
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  title: Text(email ?? 'Giriş yapıldı'),
                  subtitle: Text(switch (status.phase) {
                    SyncPhase.syncing => 'Eşitleniyor…',
                    SyncPhase.error => status.error ?? 'Eşitleme hatası',
                    _ => last == null
                        ? 'Henüz eşitlenmedi'
                        : 'Son eşitleme: ${DateFormat('d MMM HH:mm', 'tr').format(last)}',
                  }),
                  trailing: IconButton(
                    tooltip: 'Şimdi eşitle',
                    icon: const Icon(Icons.sync),
                    onPressed: status.phase == SyncPhase.syncing
                        ? null
                        : service.syncNow,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Çıkış yap'),
                    onPressed: () async {
                      final pending = await service.pendingCount();
                      if (!context.mounted) return;
                      final ok = await confirmDialog(
                        context,
                        title: 'Çıkış yapılsın mı?',
                        message: pending > 0
                            ? 'Henüz buluta gönderilmemiş $pending değişiklik var. '
                                'Çıkışta önce eşitleme denenecek; başarısız olursa bu değişiklikler kaybolur.'
                            : 'Bu cihazdaki veriler silinecek; bulutta güvende kalır ve '
                                'tekrar giriş yaptığında geri gelir.',
                        confirmLabel: 'Çıkış yap',
                      );
                      if (ok) await service.signOutAndWipe();
                    },
                  ),
                ),
              ],
            ),
        },
      ],
    );
  }
}

class AreasScreen extends ConsumerWidget {
  const AreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider).value ?? const <Area>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Alanlar')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref, null, areas.length),
        child: const Icon(Icons.add),
      ),
      body: ContentWidth(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final a in areas)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(a.color).withValues(alpha: 0.2),
                  child: Text(a.icon.isEmpty ? a.name.characters.first : a.icon),
                ),
                title: Text(a.name),
                subtitle: Text(switch (a.kind) {
                  'work' => 'İş alanı',
                  'personal' => 'Kişisel alan',
                  _ => 'Diğer',
                }),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _edit(context, ref, a, areas.length),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, Area? area, int count) async {
    final name = TextEditingController(text: area?.name ?? '');
    final icon = TextEditingController(text: area?.icon ?? '');
    var color = area?.color ?? paletteColors[count % paletteColors.length];
    var kind = area?.kind ?? 'other';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(area == null ? 'Yeni alan' : 'Alanı düzenle'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: icon,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(hintText: '📁'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: name,
                        autofocus: true,
                        decoration:
                            const InputDecoration(hintText: 'Ad (ör. Sağlık, Eğitim)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in paletteColors)
                      GestureDetector(
                        onTap: () => setState(() => color = c),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: Color(c),
                          child: color == c
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'work', label: Text('İş')),
                    ButtonSegment(value: 'personal', label: Text('Kişisel')),
                    ButtonSegment(value: 'other', label: Text('Diğer')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => setState(() => kind = v.first),
                ),
              ],
            ),
          ),
          actions: [
            if (area != null)
              TextButton(
                onPressed: () async {
                  if (await confirmDialog(context,
                      title: 'Alan silinsin mi?',
                      message: 'Bu alandaki görevler silinmez, alansız kalır.')) {
                    await ref.read(areasRepoProvider).delete(area.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Sil'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () async {
                final n = name.text.trim();
                if (n.isEmpty) return;
                final repo = ref.read(areasRepoProvider);
                if (area == null) {
                  await repo.create(
                      name: n,
                      color: color,
                      icon: icon.text.trim(),
                      kind: kind,
                      sortOrder: count);
                } else {
                  await repo.save(
                    area.id,
                    AreasCompanion(
                      name: Value(n),
                      color: Value(color),
                      icon: Value(icon.text.trim()),
                      kind: Value(kind),
                    ),
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    icon.dispose();
  }
}
