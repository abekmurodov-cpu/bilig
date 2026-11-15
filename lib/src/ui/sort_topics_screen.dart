import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../llm/llm_provider.dart';
import '../llm/llm_providers.dart';
import '../models/knowledge_item.dart';
import '../providers/knowledge_providers.dart';

/// The AI proposes topics for a category; the student renames them, moves
/// notes between them, and applies.
class SortTopicsScreen extends ConsumerStatefulWidget {
  const SortTopicsScreen({super.key, required this.category});

  final String category;

  @override
  ConsumerState<SortTopicsScreen> createState() => _SortTopicsScreenState();
}

class _SortTopicsScreenState extends ConsumerState<SortTopicsScreen> {
  /// Note id → proposed topic.
  Map<String, String>? _proposal;
  String? _error;

  /// Proposed name → name as edited.
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    _ask();
  }

  List<KnowledgeItem> get _notes =>
      ref.read(notesByCategoryProvider)[widget.category] ?? const [];

  Future<void> _ask() async {
    final strings = context.s;
    setState(() {
      _proposal = null;
      _error = null;
    });
    final llm = ref.read(llmProvider);
    if (llm == null) return;
    try {
      final proposal = await llm.suggestTopics(widget.category, _notes);
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _names
          ..clear()
          ..addAll({for (final t in proposal.values) t: t});
      });
    } on LlmException catch (e) {
      if (mounted) setState(() => _error = strings.aiFailure(e.kind, e.message));
    } catch (e) {
      if (mounted) setState(() => _error = strings.couldNotGenerate(e));
    }
  }

  Future<void> _renameGroup(String topic) async {
    final strings = context.s;
    final controller = TextEditingController(text: _names[topic]);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.renameTopic),
        content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(strings.save)),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _names[topic] = name.trim());
    }
  }

  Future<void> _moveNote(KnowledgeItem note) async {
    final groups = {..._names.keys};
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final g in groups)
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(_names[g]!),
              selected: _proposal![note.id] == g,
              onTap: () => Navigator.pop(context, g),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _proposal![note.id] = picked);
  }

  Future<void> _apply() async {
    final proposal = _proposal!;
    await ref.read(knowledgeListProvider.notifier).setTopics(widget.category, {
      for (final e in proposal.entries) e.key: _names[e.value] ?? e.value,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final theme = Theme.of(context);
    final proposal = _proposal;
    final notes = {for (final n in _notes) n.id: n};
    final groups = <String, List<KnowledgeItem>>{};
    if (proposal != null) {
      for (final e in proposal.entries) {
        final n = notes[e.key];
        if (n != null) (groups[e.value] ??= []).add(n);
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.sortIntoTopics),
        actions: [
          if (proposal != null)
            IconButton(
              tooltip: strings.tryAgain,
              icon: const Icon(Icons.refresh),
              onPressed: _ask,
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _ask, child: Text(strings.tryAgain)),
                  ],
                ),
              ),
            )
          : proposal == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(strings.sortingTopics(widget.category)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Text(strings.sortTopicsBlurb,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    for (final g in groups.entries) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.account_tree_outlined),
                                title: Text(_names[g.key] ?? g.key,
                                    style: theme.textTheme.titleMedium),
                                subtitle: Text(strings.notesCount(g.value.length)),
                                trailing: IconButton(
                                  tooltip: strings.renameTopic,
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _renameGroup(g.key),
                                ),
                              ),
                              for (final n in g.value)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.only(left: 56, right: 8),
                                  title: Text(n.front,
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: const Icon(Icons.swap_horiz, size: 18),
                                  onTap: () => _moveNote(n),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
      bottomNavigationBar: proposal == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check),
                  label: Text(strings.applyTopics(groups.length)),
                ),
              ),
            ),
    );
  }
}
