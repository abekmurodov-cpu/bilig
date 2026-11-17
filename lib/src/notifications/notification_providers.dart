import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../l10n/app_strings.dart';
import '../models/knowledge_item.dart';
import '../providers/knowledge_providers.dart';
import '../providers/settings_providers.dart';
import 'notification_service.dart';

/// Bound in `main` to the initialized service via a ProviderScope override.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError('notificationServiceProvider must be overridden');
});

/// User's reminder preference: whether a daily nudge is on and at what time.
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;

  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

class ReminderNotifier extends Notifier<ReminderSettings> {
  SettingsRepository get _s => ref.read(settingsRepositoryProvider);
  NotificationService get _service => ref.read(notificationServiceProvider);

  AppStrings get _strings => AppStrings(ref.read(languageProvider));

  @override
  ReminderSettings build() {
    // Reschedule so the notification text follows a language change.
    ref.listen(languageProvider, (_, _) {
      if (state.enabled) refresh();
    });
    return ReminderSettings(
      enabled: _s.getString(SettingsRepository.kReminderEnabled) == 'true',
      hour: _s.getInt(SettingsRepository.kReminderHour) ?? 9,
      minute: _s.getInt(SettingsRepository.kReminderMinute) ?? 0,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      final granted = await _service.requestPermission();
      if (!granted) return;
      state = state.copyWith(enabled: true);
      await refresh();
    } else {
      await _service.cancelDailyReminder();
    }
    await _s.setString(
        SettingsRepository.kReminderEnabled, enabled ? 'true' : 'false');
    state = state.copyWith(enabled: enabled);
  }

  Future<void> setTime(int hour, int minute) async {
    await _s.setInt(SettingsRepository.kReminderHour, hour);
    await _s.setInt(SettingsRepository.kReminderMinute, minute);
    state = state.copyWith(hour: hour, minute: minute);
    if (state.enabled) await refresh();
  }

  /// Plans the week's reminders from the notes' due dates: each says how
  /// many cards wait and for how long; days with nothing due stay quiet.
  /// Called again whenever notes change (a review moves due dates).
  Future<void> refresh() async {
    if (!state.enabled) return;
    final notes = ref.read(knowledgeListProvider).asData?.value ?? const <KnowledgeItem>[];
    await _service.scheduleReminders(
        reminderPlan(notes, state.hour, state.minute, _strings));
  }
}

/// When each reminder of the coming week fires and what it says.
Map<DateTime, String> reminderPlan(
    List<KnowledgeItem> notes, int hour, int minute, AppStrings strings,
    {DateTime? now}) {
  final at = now ?? DateTime.now();
  final plan = <DateTime, String>{};
  for (var day = 0; day < NotificationService.reminderDays + 1; day++) {
    final when = DateTime(at.year, at.month, at.day + day, hour, minute);
    if (!when.isAfter(at)) continue;
    final due = notes.where((n) => !n.dueDate.isAfter(when)).length;
    if (due == 0) continue;
    plan[when] = strings.reminderDue(due, (due * 20 / 60).ceil());
  }
  return plan;
}

final reminderProvider =
    NotifierProvider<ReminderNotifier, ReminderSettings>(ReminderNotifier.new);
