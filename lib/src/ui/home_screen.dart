import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers/knowledge_providers.dart';
import '../providers/study_providers.dart';
import '../models/knowledge_item.dart';
import '../practice/practice_models.dart';
import '../providers/navigation.dart';
import 'widgets/app_logo.dart';
import 'stats_screen.dart';
import 'widgets/forest_view.dart';
import 'widgets/item_tile.dart';
import 'widgets/note_detail_sheet.dart';
import 'widgets/study_cards.dart';

/// How many notes each Home section lists.
const int _sectionSize = 5;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final itemsAsync = ref.watch(knowledgeListProvider);
    final items = itemsAsync.asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 34),
            SizedBox(width: 10),
            Text('Bilig'),
          ],
        ),
        actions: [
          const _StreakButton(),
          if (items.isNotEmpty)
            IconButton(
              tooltip: strings.examMode,
              icon: const Icon(Icons.event_outlined),
              onPressed: () => showExamDialog(context, ref),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(strings.somethingWentWrong(e))),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
          }
          final recent = ref.watch(notesSortedProvider).take(_sectionSize).toList();
          final weak = [for (final n in items) if (n.isWeak) n]
            ..sort((a, b) => b.lapses != a.lapses
                ? b.lapses - a.lapses
                : a.dueDate.compareTo(b.dueDate));
          void seeAll() => ref.read(shellTabProvider.notifier).go(ShellTab.notes);
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const TodayCard(),
              const ExamCards(),
              const ForestView(),
              if (weak.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.trending_down,
                  title: strings.strugglingWith,
                  action: strings.practiseThese,
                  onAction: () => startSession(context, weak.take(20).toList(),
                      scope: PracticeScope.weakPoints),
                ),
                for (final n in weak.take(_sectionSize)) _tile(context, n),
              ],
              _SectionHeader(
                icon: Icons.schedule,
                title: strings.recentlyAdded,
                action: strings.seeAll,
                onAction: seeAll,
              ),
              for (final n in recent) _tile(context, n),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, KnowledgeItem n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ItemTile(item: n, onTap: () => showNoteDetailSheet(context, n)),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 96),
            const SizedBox(height: 16),
            Text(
              context.s.emptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.s.emptyBody,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// "🔥 7" when on a streak (a chart icon otherwise); opens Progress.
class _StreakButton extends ConsumerWidget {
  const _StreakButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = currentStreak(ref.watch(activityProvider));
    void open() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const StatsScreen()));
    if (streak == 0) {
      return IconButton(
        tooltip: context.s.progress,
        icon: const Icon(Icons.insights_outlined),
        onPressed: open,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        tooltip: context.s.progress,
        label: Text('🔥 $streak'),
        onPressed: open,
      ),
    );
  }
}
