import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_client.dart';

/// Cihaza özel tercihler (senkronize edilmez).
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.workStartMinutes = 9 * 60,
    this.workEndMinutes = 18 * 60,
    this.pomodoroWork = 25,
    this.pomodoroShortBreak = 5,
    this.pomodoroLongBreak = 15,
    this.pomodoroLongEvery = 4,
    this.remindersEnabled = true,
    this.reminderLeadMinutes = 10,
    this.aiProvider = AiProviderKind.anthropic,
    this.aiModel = '',
    this.aiBaseUrl = 'http://localhost:11434/v1',
    this.authSkipped = false,
  });

  final ThemeMode themeMode;
  final int workStartMinutes;
  final int workEndMinutes;
  final int pomodoroWork;
  final int pomodoroShortBreak;
  final int pomodoroLongBreak;
  final int pomodoroLongEvery;
  final bool remindersEnabled;
  final int reminderLeadMinutes;
  final AiProviderKind aiProvider;
  final String aiModel;
  final String aiBaseUrl;
  final bool authSkipped;

  String get effectiveAiModel =>
      aiModel.trim().isEmpty ? aiProvider.defaultModel : aiModel.trim();

  TimeOfDay get workStart =>
      TimeOfDay(hour: workStartMinutes ~/ 60, minute: workStartMinutes % 60);
  TimeOfDay get workEnd =>
      TimeOfDay(hour: workEndMinutes ~/ 60, minute: workEndMinutes % 60);

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? workStartMinutes,
    int? workEndMinutes,
    int? pomodoroWork,
    int? pomodoroShortBreak,
    int? pomodoroLongBreak,
    int? pomodoroLongEvery,
    bool? remindersEnabled,
    int? reminderLeadMinutes,
    AiProviderKind? aiProvider,
    String? aiModel,
    String? aiBaseUrl,
    bool? authSkipped,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        workStartMinutes: workStartMinutes ?? this.workStartMinutes,
        workEndMinutes: workEndMinutes ?? this.workEndMinutes,
        pomodoroWork: pomodoroWork ?? this.pomodoroWork,
        pomodoroShortBreak: pomodoroShortBreak ?? this.pomodoroShortBreak,
        pomodoroLongBreak: pomodoroLongBreak ?? this.pomodoroLongBreak,
        pomodoroLongEvery: pomodoroLongEvery ?? this.pomodoroLongEvery,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
        aiProvider: aiProvider ?? this.aiProvider,
        aiModel: aiModel ?? this.aiModel,
        aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
        authSkipped: authSkipped ?? this.authSkipped,
      );

  static AppSettings load(SharedPreferences p) {
    const d = AppSettings();
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == p.getString('themeMode'),
          orElse: () => d.themeMode),
      workStartMinutes: p.getInt('workStartMinutes') ?? d.workStartMinutes,
      workEndMinutes: p.getInt('workEndMinutes') ?? d.workEndMinutes,
      pomodoroWork: p.getInt('pomodoroWork') ?? d.pomodoroWork,
      pomodoroShortBreak:
          p.getInt('pomodoroShortBreak') ?? d.pomodoroShortBreak,
      pomodoroLongBreak: p.getInt('pomodoroLongBreak') ?? d.pomodoroLongBreak,
      pomodoroLongEvery: p.getInt('pomodoroLongEvery') ?? d.pomodoroLongEvery,
      remindersEnabled: p.getBool('remindersEnabled') ?? d.remindersEnabled,
      reminderLeadMinutes:
          p.getInt('reminderLeadMinutes') ?? d.reminderLeadMinutes,
      aiProvider: AiProviderKind.fromName(p.getString('aiProvider')),
      aiModel: p.getString('aiModel') ?? d.aiModel,
      aiBaseUrl: p.getString('aiBaseUrl') ?? d.aiBaseUrl,
      authSkipped: p.getBool('authSkipped') ?? d.authSkipped,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setString('themeMode', themeMode.name);
    await p.setInt('workStartMinutes', workStartMinutes);
    await p.setInt('workEndMinutes', workEndMinutes);
    await p.setInt('pomodoroWork', pomodoroWork);
    await p.setInt('pomodoroShortBreak', pomodoroShortBreak);
    await p.setInt('pomodoroLongBreak', pomodoroLongBreak);
    await p.setInt('pomodoroLongEvery', pomodoroLongEvery);
    await p.setBool('remindersEnabled', remindersEnabled);
    await p.setInt('reminderLeadMinutes', reminderLeadMinutes);
    await p.setString('aiProvider', aiProvider.name);
    await p.setString('aiModel', aiModel);
    await p.setString('aiBaseUrl', aiBaseUrl);
    await p.setBool('authSkipped', authSkipped);
  }
}
