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
    {PracticeScope scope = PracticeScope.due, String? category}) {
  if (queue.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PracticeSessionScreen(
      config: PracticeConfig(
          method: PracticeMethod.flashcard, scope: scope, category: category),
      queue: queue,
    ),
  ));
}

/// What to study next when nothing is due: the notes due soonest.
List<KnowledgeItem> soonestDue(List<KnowledgeItem> all, int count) =>
    (List.of(all)..sort((a, b) => a.dueDate.compareTo(b.dueDate)))
        .take(count)
        .toList();

/// Today's reviews: how many and how long, with "Review" and "Quick 5".
/// Small sessions are what get a student to start.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final scheme = Theme.of(context).colorScheme;
    final due = ref.watch(dueItemsProvider);
    final all = ref.watch(notesSortedProvider);
    final minutes = (due.length * _perCard.inSeconds / 60).ceil();
    final quick = due.isNotEmpty
        ? due.take(quickCount).toList()
        : soonestDue(all, quickCount);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: due.isEmpty ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(due.isEmpty ? Icons.check_circle_outline : Icons.bolt,
                  color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due.isEmpty ? strings.allCaughtUp : strings.dueToday(due.length),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      due.isEmpty ? strings.practiseAhead : strings.aboutMinutes(minutes),
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (quick.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => startSession(context, quick),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: Text(strings.quickFive),
                ),
              if (due.isNotEmpty)
                FilledButton(
                  onPressed: () => startSession(context, due),
                  child: Text(strings.review),
                ),
            ],
          ),
        ],
      ),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
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
        ],
      ),
    );
  }
}

/// Picks a category and an exam date (or removes the exam).
Future<void> showExamDialog(BuildContext context, WidgetRef ref) async {
  final categories = ref.read(categoriesProvider);
  if (categories.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.s.examNeedsCategory)));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _ExamDialog(categories: categories),
  );
}

class _ExamDialog extends ConsumerStatefulWidget {
  const _ExamDialog({required this.categories});

  final List<String> categories;

  @override
  ConsumerState<_ExamDialog> createState() => _ExamDialogState();
}

class _ExamDialogState extends ConsumerState<_ExamDialog> {
  late String _category = widget.categories.first;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _date = ref.read(examsProvider)[_category];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final existing = ref.watch(examsProvider)[_category];
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
                labelText: strings.category, border: const OutlineInputBorder()),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: c, child: Text(c)),
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
