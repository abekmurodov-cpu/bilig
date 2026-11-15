import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers/knowledge_providers.dart';
import '../providers/stats.dart';
import '../providers/study_providers.dart';

/// Activity calendar steps, empty → most reviews (one hue, light → dark;
/// green to match the trees). Dark mode has its own steps, dark → bright.
const _greensLight = [Color(0xFFE6EBE3), Color(0xFFC3E3A9), Color(0xFF8CCB6B), Color(0xFF4FA343), Color(0xFF2B6E2A)];
const _greensDark = [Color(0xFF2A2F2A), Color(0xFF1F4A26), Color(0xFF2E7A35), Color(0xFF4FAE4A), Color(0xFF8DDB72)];

/// Progress: streaks, the activity calendar, how much is learned, how well
/// it is remembered, and what is coming up this week.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final activity = ref.watch(activityProvider);
    final notes = ref.watch(notesSortedProvider);
    final stages = noteStages(notes);
    final recall = averageRecall(notes);
    final streak = currentStreak(activity);
    final best = math.max(longestStreak(activity), streak);
    return Scaffold(
      appBar: AppBar(title: Text(strings.progress)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                  child: _StatTile(
                      value: '🔥 $streak', label: strings.dayStreak(streak), hero: true)),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(value: '$best', label: strings.bestStreak)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatTile(
                      value: recall == null ? '—' : '${(recall * 100).round()}%',
                      label: strings.rememberNow)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _StatTile(value: '${stages.learned}', label: strings.learned)),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(value: '${stages.learning}', label: strings.learning)),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(value: '${stages.fresh}', label: strings.newNotes)),
            ],
          ),
          _Section(title: strings.activity, child: _ActivityCalendar(activity: activity)),
          _Section(
            title: strings.recallByWeek,
            subtitle: strings.recallByWeekBlurb,
            child: _RecallBars(weeks: weeklyRecall(activity)),
          ),
          _Section(
            title: strings.comingUp,
            child: _UpcomingBars(counts: upcomingReviews(notes)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null)
            Text(subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A headline number with its label.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.hero = false});

  final String value;
  final String label;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: hero
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// A GitHub-style grid of study days: one column per week (Monday on top),
/// darker for more reviews. Each day shows its count on hover / long-press.
class _ActivityCalendar extends StatelessWidget {
  const _ActivityCalendar({required this.activity});

  final Map<String, DayActivity> activity;

  static const double _cell = 13;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ramp = dark ? _greensDark : _greensLight;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxReviews =
        activity.values.fold<int>(0, (m, d) => math.max(m, d.reviews));
    int level(int reviews) {
      if (reviews == 0) return 0;
      if (maxReviews <= 4) return math.min(4, reviews);
      return 1 + math.min(3, (reviews * 4 / (maxReviews + 1)).floor());
    }

    final localizations = MaterialLocalizations.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final weeks = math.max(4, ((constraints.maxWidth + _gap) / (_cell + _gap)).floor());
      final firstMonday = today
          .subtract(Duration(days: today.weekday - 1))
          .subtract(Duration(days: 7 * (weeks - 1)));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var w = 0; w < weeks; w++)
                Padding(
                  padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : _gap),
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        () {
                          final day = DateTime(firstMonday.year, firstMonday.month,
                              firstMonday.day + w * 7 + d);
                          if (day.isAfter(today)) {
                            return const SizedBox(width: _cell, height: _cell + _gap);
                          }
                          final reviews = activity[dayKey(day)]?.reviews ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: Tooltip(
                              message:
                                  '${localizations.formatMediumDate(day)} · ${strings.reviewsCount(reviews)}',
                              child: Container(
                                width: _cell,
                                height: _cell,
                                decoration: BoxDecoration(
                                  color: ramp[level(reviews)],
                                  borderRadius: BorderRadius.circular(3),
                                  border: day == today
                                      ? Border.all(color: theme.colorScheme.outline, width: 1)
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }(),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(strings.less, style: theme.textTheme.labelSmall),
              const SizedBox(width: 4),
              for (final c in ramp)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 2),
                  decoration:
                      BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
                ),
              const SizedBox(width: 2),
              Text(strings.more, style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      );
    });
  }
}

/// Vertical bars over a recessive baseline, one value per slot, with the
/// value on hover / long-press and a label under each bar.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.values,
    required this.labels,
    required this.tooltips,
    this.max,
    this.valueLabels = const {},
  });

  final List<double> values;
  final List<String> labels;
  final List<String> tooltips;
  final double? max;

  /// Values printed above some bars (selectively, never all).
  final Map<int, String> valueLabels;

  static const double _height = 120;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = max ?? values.fold<double>(0, math.max);
    return Column(
      children: [
        SizedBox(
          height: _height + 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Tooltip(
                    message: tooltips[i],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (valueLabels[i] != null)
                            Text(valueLabels[i]!, style: theme.textTheme.labelSmall),
                          const SizedBox(height: 2),
                          Container(
                            height: top <= 0
                                ? 0
                                : math.max(values[i] > 0 ? 3.0 : 0, _height * values[i] / top),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius:
                                  const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Text(l,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecallBars extends StatelessWidget {
  const _RecallBars({required this.weeks});

  final List<({DateTime start, int reviews, int correct})> weeks;

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    if (weeks.every((w) => w.reviews == 0)) return Text(strings.noReviewsYet);
    final localizations = MaterialLocalizations.of(context);
    final pct = [
      for (final w in weeks) w.reviews == 0 ? 0.0 : w.correct * 100 / w.reviews,
    ];
    // Label only the latest week that had reviews.
    final lastIndex = weeks.lastIndexWhere((w) => w.reviews > 0);
    return _Bars(
      values: pct,
      max: 100,
      labels: [for (final w in weeks) '${w.start.day}.${w.start.month}'],
      tooltips: [
        for (var i = 0; i < weeks.length; i++)
          weeks[i].reviews == 0
              ? '${localizations.formatShortMonthDay(weeks[i].start)} · ${strings.reviewsCount(0)}'
              : '${localizations.formatShortMonthDay(weeks[i].start)} · ${pct[i].round()}% · ${strings.reviewsCount(weeks[i].reviews)}',
      ],
      valueLabels: {lastIndex: '${pct[lastIndex].round()}%'},
    );
  }
}

class _UpcomingBars extends StatelessWidget {
  const _UpcomingBars({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final days = [for (var i = 0; i < counts.length; i++) DateTime(now.year, now.month, now.day + i)];
    final busiest = counts.indexOf(counts.fold(0, math.max));
    return _Bars(
      values: [for (final c in counts) c.toDouble()],
      labels: [
        for (var i = 0; i < days.length; i++)
          i == 0
              ? strings.today
              : localizations.narrowWeekdays[days[i].weekday % 7],
      ],
      tooltips: [
        for (var i = 0; i < days.length; i++)
          '${localizations.formatMediumDate(days[i])} · ${strings.reviewsCount(counts[i])}',
      ],
      valueLabels: {
        0: '${counts[0]}',
        if (busiest > 0 && counts[busiest] > 0) busiest: '${counts[busiest]}',
      },
    );
  }
}
