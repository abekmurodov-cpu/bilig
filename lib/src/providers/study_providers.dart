import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import 'settings_providers.dart';

/// A calendar day as `yyyy-mm-dd`, the key for daily activity.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Exam dates per category. While an exam is ahead, that category's reviews
/// are kept before the day and come a little sooner (see SpacedRepetition).
class ExamsNotifier extends Notifier<Map<String, DateTime>> {
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  @override
  Map<String, DateTime> build() {
    final raw = _settings.getString(SettingsRepository.kExams);
    if (raw == null) return const {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          '${e.key}': DateTime.parse('${e.value}'),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Sets (or with null, clears) the exam date of [category].
  Future<void> set(String category, DateTime? date) async {
    final next = {...state};
    if (date == null) {
      next.remove(category);
    } else {
      next[category] = _dateOnly(date);
    }
    state = next;
    await _settings.setString(
      SettingsRepository.kExams,
      next.isEmpty
          ? null
          : jsonEncode({for (final e in next.entries) e.key: dayKey(e.value)}),
    );
  }

  /// The exam of [category] if it is still ahead (today counts).
  DateTime? upcoming(String? category, {DateTime? now}) {
    if (category == null) return null;
    final date = state[category.trim()];
    if (date == null) return null;
    return date.isBefore(_dateOnly(now ?? DateTime.now())) ? null : date;
  }
}

final examsProvider =
    NotifierProvider<ExamsNotifier, Map<String, DateTime>>(ExamsNotifier.new);

/// One day's reviewing.
class DayActivity {
  const DayActivity({this.reviews = 0, this.correct = 0});

  final int reviews;
  final int correct;

  DayActivity add({required bool correct, int sign = 1}) => DayActivity(
        reviews: (reviews + sign).clamp(0, 1 << 30),
        correct: (this.correct + (correct ? sign : 0)).clamp(0, 1 << 30),
      );
}

/// Reviews per day, for streaks, the activity calendar and stats. Only daily
/// totals are kept, so it stays small.
class ActivityNotifier extends Notifier<Map<String, DayActivity>> {
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  @override
  Map<String, DayActivity> build() {
    final raw = _settings.getString(SettingsRepository.kActivity);
    if (raw == null) return const {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          '${e.key}': DayActivity(
            reviews: ((e.value as List)[0] as num).toInt(),
            correct: ((e.value as List)[1] as num).toInt(),
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Counts one review on [at]'s day; with [undo], takes one back.
  Future<void> record({required bool correct, DateTime? at, bool undo = false}) async {
    final key = dayKey(at ?? DateTime.now());
    final next = {...state};
    next[key] = (next[key] ?? const DayActivity())
        .add(correct: correct, sign: undo ? -1 : 1);
    if (next[key]!.reviews == 0) next.remove(key);
    state = next;
    await _settings.setString(
      SettingsRepository.kActivity,
      jsonEncode({
        for (final e in next.entries) e.key: [e.value.reviews, e.value.correct],
      }),
    );
  }
}

final activityProvider =
    NotifierProvider<ActivityNotifier, Map<String, DayActivity>>(
        ActivityNotifier.new);

/// Days in a row with at least one review, ending today (or yesterday, so a
/// streak isn't "lost" before today's session).
int currentStreak(Map<String, DayActivity> activity, {DateTime? now}) {
  var day = _dateOnly(now ?? DateTime.now());
  if (!activity.containsKey(dayKey(day))) {
    day = day.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (activity.containsKey(dayKey(day))) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// The longest run of study days ever.
int longestStreak(Map<String, DayActivity> activity) {
  // UTC days, so a daylight-saving change doesn't break a run.
  final days = [for (final k in activity.keys) DateTime.parse('${k}T00:00:00Z')]
    ..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in days) {
    run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}
