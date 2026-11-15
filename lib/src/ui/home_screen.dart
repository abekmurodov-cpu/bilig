import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers/knowledge_providers.dart';
import 'capture_screen.dart';
import 'widgets/app_logo.dart';
import 'widgets/item_tile.dart';
import 'widgets/note_detail_sheet.dart';
import 'widgets/study_cards.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (items.isNotEmpty)
            IconButton(
              tooltip: context.s.examMode,
              icon: const Icon(Icons.event_outlined),
              onPressed: () => showExamDialog(context, ref),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCapture(context),
        icon: const Icon(Icons.add),
        label: Text(context.s.capture),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(context.s.somethingWentWrong(e))),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
          }
          return Column(
            children: [
              const TodayCard(),
              const ExamCards(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) => ItemTile(
                    item: items[i],
                    onTap: () => showNoteDetailSheet(context, items[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCapture(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
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
