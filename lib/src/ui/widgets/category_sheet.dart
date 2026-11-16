import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../models/note_search.dart';
import '../../practice/practice_models.dart';
import '../../providers/knowledge_providers.dart';
import '../../providers/navigation.dart';
import '../capture_screen.dart';
import 'category_tree.dart';
import 'note_detail_sheet.dart';
import 'share_category.dart';
import 'study_cards.dart';
import 'tree_model.dart';

/// A category at a glance (tapping a tree opens it): practise all of it or
/// one topic, see its notes or its tree, add a note, sort it into topics
/// with the AI, rename, share.
Future<void> showCategorySheet(BuildContext context, String category) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategorySheet(category: category, host: context),
  );
}

/// Study order for a group of notes: not yet known first, then due soonest.
List<KnowledgeItem> studyOrder(Iterable<KnowledgeItem> notes) => List.of(notes)
  ..sort((a, b) {
    int rank(KnowledgeItem n) => n.lastCorrect == true ? 1 : 0;
    final r = rank(a) - rank(b);
    return r != 0 ? r : a.dueDate.compareTo(b.dueDate);
  });

class _CategorySheet extends ConsumerWidget {
  const _CategorySheet({required this.category, required this.host});

  final String category;

  /// The screen the sheet was opened from: what it opens goes on top of
  /// that, as the sheet closes first.
  final BuildContext host;

  bool get _ungrouped => category == kUngroupedCategory;

  void _seeNotes(BuildContext context, WidgetRef ref, {String? topic}) {
    Navigator.pop(context);
    ref.read(notesFilterRequestProvider.notifier).show({
      if (topic != null) topicKey(category, topic) else if (_ungrouped) '' else category,
    });
    ref.read(shellTabProvider.notifier).go(ShellTab.notes);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, {String? topic}) async {
    final strings = context.s;
    final controller = TextEditingController(text: topic ?? category);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(topic == null ? strings.renameCategory : strings.renameTopic),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              helperText: topic == null ? null : strings.emptyRemovesTopic),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(strings.save)),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await ref.read(knowledgeListProvider.notifier).rename(category, name, topic: topic);
    if (topic == null && context.mounted && name.trim().isNotEmpty) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = ref.watch(notesByCategoryProvider)[category] ?? const <KnowledgeItem>[];
    final topics = ref.watch(topicInfoProvider)[category] ?? const <CategoryInfo>[];
    final learned = notes.where((n) => leafLook(n) == LeafLook.green).length;
    final loose = notes.where((n) => n.topic == null).toList();
    void practise(List<KnowledgeItem> queue, {String? topic}) {
      Navigator.pop(context);
      startSession(host, studyOrder(queue),
          scope: PracticeScope.category, category: category, topic: topic);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.park_outlined, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(categoryDisplayName(context, category),
                        style: theme.textTheme.titleLarge),
                    Text(strings.learnedOf(learned, notes.length),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => _rename(context, ref),
                  'share' => showShareCategory(host, category, notes),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (!_ungrouped)
                    PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(strings.renameCategory)),
                    ),
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                        leading: const Icon(Icons.ios_share),
                        title: Text(strings.shareCategory)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: notes.isEmpty ? 0 : learned / notes.length,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: notes.isEmpty ? null : () => practise(notes),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(strings.practiseAll),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _seeNotes(context, ref),
                  icon: const Icon(Icons.view_agenda_outlined),
                  label: Text(strings.seeNotes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final ordered = leafOrder(notes);
                  Navigator.of(host).push(MaterialPageRoute(
                    builder: (_) => TreeViewerScreen(
                      category: category,
                      notes: ordered,
                      model: TreeModel.generate(count: ordered.length, seed: category),
                      onLeafTap: (n) => showNoteDetailSheet(host, n),
                    ),
                  ));
                },
                icon: const Icon(Icons.park_outlined),
                label: Text(strings.viewTree),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(host).push(MaterialPageRoute(
                    builder: (_) => CaptureScreen(
                        initialCategory: _ungrouped ? null : category),
                  ));
                },
                icon: const Icon(Icons.add),
                label: Text(strings.addNote),
              ),
            ],
          ),
          if (!_ungrouped) ...[
            const Divider(height: 32),
            Row(
              children: [
                Expanded(child: Text(strings.topics, style: theme.textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: notes.isEmpty
                      ? null
                      : () {
                          final messenger = ScaffoldMessenger.of(host);
                          _seeNotes(context, ref);
                          messenger.showSnackBar(SnackBar(
                            content: Text(strings.organizeHint),
                            duration: const Duration(seconds: 6),
                          ));
                        },
                  icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                  label: Text(strings.organizeNotes),
                ),
              ],
            ),
            if (topics.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(strings.noTopics,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            for (final t in topics)
              _TopicRow(
                name: t.name,
                notes: [for (final n in notes) if (n.topic == t.name) n],
                onPractise: (queue) => practise(queue, topic: t.name),
                onOpen: () => _seeNotes(context, ref, topic: t.name),
                onRename: () => _rename(context, ref, topic: t.name),
              ),
            if (topics.isNotEmpty && loose.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(strings.withoutTopic(loose.length),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
          ],
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.name,
    required this.notes,
    required this.onPractise,
    required this.onOpen,
    required this.onRename,
  });

  final String name;
  final List<KnowledgeItem> notes;
  final void Function(List<KnowledgeItem>) onPractise;
  final VoidCallback onOpen;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final learned = notes.where((n) => leafLook(n) == LeafLook.green).length;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 4),
      leading: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          value: notes.isEmpty ? 0 : learned / notes.length,
          strokeWidth: 4,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
      title: Text(name),
      subtitle: Text(context.s.learnedOf(learned, notes.length)),
      onTap: onOpen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.s.renameTopic,
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onRename,
          ),
          IconButton.filledTonal(
            tooltip: context.s.practiseTopic,
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => onPractise(notes),
          ),
        ],
      ),
    );
  }
}
