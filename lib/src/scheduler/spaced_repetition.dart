import 'dart:math' as math;

import '../models/knowledge_item.dart';

/// How well the user recalled an item during review: FSRS's four ratings.
/// [quality] is the older SM-2 0–5 score, still used to count correct
/// answers (≥3).
enum ReviewGrade {
  again, // failed to recall
  hard, // recalled with serious difficulty
  good, // recalled correctly
  easy; // recalled effortlessly

  int get quality => switch (this) {
        ReviewGrade.again => 1,
        ReviewGrade.hard => 3,
        ReviewGrade.good => 4,
        ReviewGrade.easy => 5,
      };

  String get label => switch (this) {
        ReviewGrade.again => 'Again',
        ReviewGrade.hard => 'Hard',
        ReviewGrade.good => 'Good',
        ReviewGrade.easy => 'Easy',
      };
}

/// The FSRS spaced-repetition scheduler (FSRS-5, default parameters) — the
/// algorithm Anki uses today. It models each note's memory with a
/// [KnowledgeItem.stability] (days until recall odds fall to 90%) and a
/// [KnowledgeItem.difficulty] (1–10), and schedules the next review for when
/// recall odds reach [desiredRetention]. Compared with SM-2 it reaches the
/// same memory with noticeably fewer reviews.
///
/// The SM-2-era counters ([KnowledgeItem.repetitions], [KnowledgeItem.lapses],
/// [KnowledgeItem.intervalDays]) are still kept up to date: other features
/// (weak points, question rotation, the tree colours) read them, and a note
/// reviewed before FSRS seeds its memory state from them.
class SpacedRepetition {
  const SpacedRepetition({this.desiredRetention = 0.9});

  /// Target odds of remembering a note when it comes up for review.
  final double desiredRetention;

  /// Retention aimed for while a category's exam is coming up: reviews come
  /// sooner, so more is fresh on the day.
  static const double examRetention = 0.95;

  static const List<double> w = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, //
    1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, //
    2.9898, 0.51655, 0.6621,
  ];
  static const double _decay = -0.5;
  static const double _factor = 19 / 81;
  static const int _maxInterval = 36500;

  static int _g(ReviewGrade grade) => switch (grade) {
        ReviewGrade.again => 1,
        ReviewGrade.hard => 2,
        ReviewGrade.good => 3,
        ReviewGrade.easy => 4,
      };

  /// Odds of recalling a note [elapsedDays] after its last review.
  static double retrievability(double elapsedDays, double stability) =>
      math.pow(1 + _factor * elapsedDays / stability, _decay).toDouble();

  static double _initialStability(int g) => w[g - 1];

  static double _initialDifficulty(int g) =>
      (w[4] - math.exp(w[5] * (g - 1)) + 1).clamp(1.0, 10.0);

  /// Days until recall odds fall to [retention].
  static double _interval(double stability, double retention) =>
      stability / _factor * (math.pow(retention, 1 / _decay) - 1);

  /// The memory state a note reviewed only under SM-2 starts FSRS with.
  static ({double stability, double difficulty}) seedFromSm2(KnowledgeItem item) => (
        stability: math.max(1, item.intervalDays).toDouble(),
        // SM-2 ease 2.5 (the default) ≈ medium difficulty; harder notes
        // dropped towards 1.3.
        difficulty: (10 - (item.easeFactor - 1.3) * 4).clamp(1.0, 10.0),
      );

  /// Reschedules [item] after a review graded [grade]. With an [examDate]
  /// in the future, the next review is kept before the exam and comes a bit
  /// sooner, so everything gets one more look before the day.
  KnowledgeItem schedule(
    KnowledgeItem item,
    ReviewGrade grade, {
    DateTime? now,
    DateTime? examDate,
  }) {
    final reviewedAt = now ?? DateTime.now();
    final today = DateTime(reviewedAt.year, reviewedAt.month, reviewedAt.day);
    final g = _g(grade);
    final correct = g >= 3 || grade == ReviewGrade.hard;
    final examAhead = examDate != null && examDate.isAfter(today);
    final retention = examAhead ? examRetention : desiredRetention;

    double stability;
    double difficulty;
    var s = item.stability;
    var d = item.difficulty;
    final last = item.lastReviewedAt;
    if ((s == null || d == null) && last != null) {
      final seed = seedFromSm2(item);
      s = seed.stability;
      d = seed.difficulty;
    }
    if (s == null || d == null || last == null) {
      // First review ever.
      stability = _initialStability(g);
      difficulty = _initialDifficulty(g);
    } else {
      final elapsed = reviewedAt.difference(last).inHours / 24;
      final nextD = d - w[6] * (g - 3);
      final damped = d + (nextD - d) * (10 - d) / 9;
      difficulty =
          (w[7] * _initialDifficulty(4) + (1 - w[7]) * damped).clamp(1.0, 10.0);
      if (elapsed < 1) {
        // Reviewed again the same day: a small, grade-based nudge.
        stability = s * math.exp(w[17] * (g - 3 + w[18]));
      } else {
        final r = retrievability(elapsed, s);
        if (g == 1) {
          stability = math.min(
              s,
              w[11] *
                  math.pow(difficulty, -w[12]) *
                  (math.pow(s + 1, w[13]) - 1) *
                  math.exp(w[14] * (1 - r)));
        } else {
          final hardPenalty = g == 2 ? w[15] : 1.0;
          final easyBonus = g == 4 ? w[16] : 1.0;
          stability = s *
              (math.exp(w[8]) *
                      (11 - difficulty) *
                      math.pow(s, -w[9]) *
                      (math.exp(w[10] * (1 - r)) - 1) *
                      hardPenalty *
                      easyBonus +
                  1);
        }
      }
    }
    stability = math.max(0.1, stability);

    var intervalDays = g == 1
        ? 1
        : _interval(stability, retention).round().clamp(1, _maxInterval);
    if (examAhead) {
      // Never schedule past the exam: the last review lands the day before.
      final daysLeft = examDate.difference(today).inDays;
      if (intervalDays >= daysLeft) intervalDays = math.max(1, daysLeft - 1);
    }

    return item.copyWith(
      stability: stability,
      difficulty: difficulty,
      repetitions: correct ? item.repetitions + 1 : 0,
      intervalDays: intervalDays,
      lastReviewedAt: reviewedAt,
      dueDate: today.add(Duration(days: intervalDays)),
      updatedAt: reviewedAt,
      lastCorrect: g >= 2,
      lapses: g == 1 ? item.lapses + 1 : item.lapses,
    );
  }
}
