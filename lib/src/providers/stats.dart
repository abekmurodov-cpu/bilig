import 'dart:math' as math;

import '../models/knowledge_item.dart';
import '../scheduler/spaced_repetition.dart';
import 'study_providers.dart';

/// Next review this far away (or more) counts a note as learned.
const int learnedAfterDays = 21;

/// How many notes are new (never reviewed), learning, and learned.
({int fresh, int learning, int learned}) noteStages(List<KnowledgeItem> notes) {
  var fresh = 0, learning = 0, learned = 0;
  for (final n in notes) {
    if (n.lastReviewedAt == null) {
      fresh++;
    } else if (n.lastCorrect == true && n.intervalDays >= learnedAfterDays) {
      learned++;
    } else {
      learning++;
    }
  }
  return (fresh: fresh, learning: learning, learned: learned);
}

/// The average odds, right now, of recalling a reviewed note (FSRS), or null
/// before anything has been reviewed.
double? averageRecall(List<KnowledgeItem> notes, {DateTime? now}) {
  final at = now ?? DateTime.now();
  var sum = 0.0;
  var count = 0;
  for (final n in notes) {
    final last = n.lastReviewedAt;
    if (last == null) continue;
    final stability = n.stability ?? math.max(1, n.intervalDays).toDouble();
    final days = math.max(0, at.difference(last).inHours / 24);
    sum += SpacedRepetition.retrievability(days.toDouble(), stability);
    count++;
  }
  return count == 0 ? null : sum / count;
}

/// Reviews coming up on each of the next [days] days; today includes
/// anything overdue.
List<int> upcomingReviews(List<KnowledgeItem> notes, {DateTime? now, int days = 7}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final out = List.filled(days, 0);
  for (final n in notes) {
    final due = DateTime(n.dueDate.year, n.dueDate.month, n.dueDate.day);
    final offset = due.difference(today).inDays;
    if (offset < days) out[math.max(0, offset)]++;
  }
  return out;
}

/// Reviews and correct answers per week (Monday-based) for the last [weeks]
/// weeks, oldest first.
List<({DateTime start, int reviews, int correct})> weeklyRecall(
    Map<String, DayActivity> activity,
    {DateTime? now,
    int weeks = 8}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final thisWeek = today.subtract(Duration(days: today.weekday - 1));
  return [
    for (var w = weeks - 1; w >= 0; w--)
      () {
        final start = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * w);
        var reviews = 0, correct = 0;
        for (var d = 0; d < 7; d++) {
          final day = activity[dayKey(DateTime(start.year, start.month, start.day + d))];
          reviews += day?.reviews ?? 0;
          correct += day?.correct ?? 0;
        }
        return (start: start, reviews: reviews, correct: correct);
      }(),
  ];
}
