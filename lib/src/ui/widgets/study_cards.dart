import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../practice/practice_models.dart';
import '../../providers/knowledge_providers.dart';
import '../../providers/study_providers.dart';
import '../practice/practice_session_screen.dart';

/// Rough time per flashcard, for "about N min".
const Duration _perCard = Duration(seconds: 20);

/// Notes in Quick 5.
const int quickCount = 5;

/// Starts a flashcard session over [queue].
void startSession(BuildContext context, List<KnowledgeItem> queue,
    {PracticeScope scope = PracticeScope.due, String? category, String? topic}) {
  if (queue.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PracticeSessionScreen(
      config: PracticeConfig(
          method: PracticeMethod.flashcard,
          scope: scope,
          category: category,
          topic: topic),
      queue: queue,
    ),
  ));
}

/// What to study next when nothing is due: the notes due soonest.
List<KnowledgeItem> soonestDue(List<KnowledgeItem> all, int count) =>
    (List.of(all)..sort((a, b) => a.dueDate.compareTo(b.dueDate)))
        .take(count)
        .toList();

/// Today: the daily goal ring, the week's study days, what is due and how
/// long it takes, with "Review" and "Quick 5". Small sessions are what get
/// a student to start.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  Future<void> _pickGoal(BuildContext context, WidgetRef ref) async {
    final strings = context.s;
    final current = ref.read(dailyGoalProvider);
    final goal = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.dailyGoal),
        children: [
          for (final g in DailyGoalNotifier.choices)
            ListTile(
              leading: Icon(g == current ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(strings.reviewsADay(g)),
              onTap: () => Navigator.pop(context, g),
            ),
        ],
      ),
    );
    if (goal != null) await ref.read(dailyGoalProvider.notifier).set(goal);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = ref.watch(dueItemsProvider);
    final all = ref.watch(notesSortedProvider);
    final activity = ref.watch(activityProvider);
    final goal = ref.watch(dailyGoalProvider);
    final done = activity[dayKey(DateTime.now())]?.reviews ?? 0;
    final minutes = (due.length * _perCard.inSeconds / 60).ceil();
    final quick = due.isNotEmpty
        ? due.take(quickCount).toList()
        : soonestDue(all, quickCount);
    final onCard = scheme.onPrimaryContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tooltip(
                message: strings.dailyGoal,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _pickGoal(context, ref),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: (done / goal).clamp(0.0, 1.0)),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, v, _) => CircularProgressIndicator(
                            value: v,
                            strokeWidth: 7,
                            strokeCap: StrokeCap.round,
                            color: done >= goal ? const Color(0xFF2E9E4F) : scheme.primary,
                            backgroundColor: scheme.surface.withValues(alpha: 0.6),
                          ),
                        ),
                        Center(
                          child: done >= goal
                              ? const Icon(Icons.check_rounded,
                                  size: 30, color: Color(0xFF2E9E4F))
                              : Text('$done/$goal',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                      color: onCard, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due.isEmpty ? strings.allCaughtUp : strings.dueToday(due.length),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: onCard, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      due.isEmpty ? strings.practiseAhead : strings.aboutMinutes(minutes),
                      style: theme.textTheme.bodyMedium?.copyWith(color: onCard),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done >= goal ? strings.goalReached : strings.goalLeft(goal - done),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: onCard.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _WeekStrip(activity: activity),
          const SizedBox(height: 14),
          Row(
            children: [
              if (quick.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: onCard,
                        side: BorderSide(color: onCard.withValues(alpha: 0.3))),
                    onPressed: () => startSession(context, quick),
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: Text(strings.quickFive),
                  ),
                ),
              if (quick.isNotEmpty && due.isNotEmpty) const SizedBox(width: 10),
              if (due.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => startSession(context, due),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(strings.review),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// This week, a day a column: filled when studied, ringed for today.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.activity});

  final Map<String, DayActivity> activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final local = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Weekday of today counted from the locale's first day of the week.
    final first = local.firstDayOfWeekIndex; // 0 = Sunday
    final offset = (today.weekday % 7 - first + 7) % 7;
    final start = DateTime(today.year, today.month, today.day - offset);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final day = DateTime(start.year, start.month, start.day + i);
            final studied = activity.containsKey(dayKey(day));
            final isToday = day == today;
            final future = day.isAfter(today);
            return Column(
              children: [
                Text(local.narrowWeekdays[day.weekday % 7],
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer
                            .withValues(alpha: future ? 0.4 : 0.8),
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
                const SizedBox(height: 4),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: studied
                        ? const Color(0xFFF08C2E)
                        : scheme.surface.withValues(alpha: future ? 0.25 : 0.5),
                    border: isToday
                        ? Border.all(color: scheme.onPrimaryContainer, width: 1.6)
                        : null,
                  ),
                  child: studied
                      ? const Icon(Icons.local_fire_department, size: 16, color: Colors.white)
                      : null,
                ),
              ],
            );
          }),
      ],
    );
  }
}

/// Upcoming exams with a countdown, how ready the category is, and "Study".
class ExamCards extends ConsumerWidget {
  const ExamCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(examsProvider);
    final all = ref.watch(notesSortedProvider);
    final today = DateTime.now();
    final upcoming = [
      for (final e in exams.entries)
        if (!e.value.isBefore(DateTime(today.year, today.month, today.day))) e,
    ]..sort((a, b) => a.value.compareTo(b.value));
    return Column(
      children: [
        for (final e in upcoming)
          _ExamCard(
            category: e.key,
            date: e.value,
            notes: [for (final n in all) if (n.category?.trim() == e.key) n],
          ),
      ],
    );
  }
}

class _ExamCard extends ConsumerWidget {
  const _ExamCard({required this.category, required this.date, required this.notes});

  final String category;
  final DateTime date;
  final List<KnowledgeItem> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final days = DateTime(date.year, date.month, date.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final ready = notes.where((n) => n.lastCorrect == true).length;
    final progress = notes.isEmpty ? 0.0 : ready / notes.length;
    // Not yet known first, then whatever is due soonest.
    final queue = List.of(notes)
      ..sort((a, b) {
        int rank(KnowledgeItem n) => n.lastCorrect == true ? 1 : 0;
        final r = rank(a) - rank(b);
        return r != 0 ? r : a.dueDate.compareTo(b.dueDate);
      });
    // Tapping the card (or the pencil) changes or removes the exam date.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Material(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showExamDialog(context, ref, category: category),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
        children: [
          Icon(Icons.event, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.examIn(category, days),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: progress, minHeight: 6),
                ),
                const SizedBox(height: 4),
                Text(strings.examReady(ready, notes.length),
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: queue.isEmpty
                ? null
                : () => startSession(context, queue,
                    scope: PracticeScope.category, category: category),
            child: Text(strings.study),
          ),
          IconButton(
            tooltip: strings.editExam,
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => showExamDialog(context, ref, category: category),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }
}

/// Picks a category and an exam date, or changes or removes one already set.
/// Opens on [category] when given (an exam card), else on the soonest exam
/// already set, else on the first category.
Future<void> showExamDialog(BuildContext context, WidgetRef ref,
    {String? category}) async {
  final exams = ref.read(examsProvider);
  // Categories with an exam stay pickable even if their notes moved away.
  final categories = {
    ...ref.read(categoriesProvider),
    ...exams.keys,
    ?category,
  }.toList();
  if (categories.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.s.examNeedsCategory)));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _ExamDialog(
      categories: categories,
      initial: category ?? _soonestExam(exams) ?? categories.first,
    ),
  );
}

String? _soonestExam(Map<String, DateTime> exams) {
  final today = DateUtils.dateOnly(DateTime.now());
  final ahead = [for (final e in exams.entries) if (!e.value.isBefore(today)) e]
    ..sort((a, b) => a.value.compareTo(b.value));
  return ahead.isEmpty ? null : ahead.first.key;
}

class _ExamDialog extends ConsumerStatefulWidget {
  const _ExamDialog({required this.categories, required this.initial});

  final List<String> categories;
  final String initial;

  @override
  ConsumerState<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends ConsumerState<_ExamDialog> {
  late String _category = widget.initial;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _date = ref.read(examsProvider)[_category];
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = _date;
    final picked = await showDatePicker(
      context: context,
      // A date already passed can't be offered; start from today then.
      initialDate: current == null
          ? today.add(const Duration(days: 14))
          : current.isBefore(today)
              ? today
              : current,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final exams = ref.watch(examsProvider);
    final existing = exams[_category];
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.examMode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.examBlurb, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: strings.category),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(
                  value: c,
                  child: Text(exams[c] == null
                      ? c
                      : '$c · ${localizations.formatMediumDate(exams[c]!)}'),
                ),
            ],
            onChanged: (c) => setState(() {
              _category = c!;
              _date = ref.read(examsProvider)[c];
            }),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(_date == null
                ? strings.pickExamDate
                : localizations.formatMediumDate(_date!)),
          ),
        ],
      ),
      actions: [
        if (existing != null)
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await ref.read(examsProvider.notifier).set(_category, null);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(strings.removeExam),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
        FilledButton(
          onPressed: _date == null
              ? null
              : () async {
                  await ref.read(examsProvider.notifier).set(_category, _date);
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(strings.save),
        ),
      ],
    );
  }
}
