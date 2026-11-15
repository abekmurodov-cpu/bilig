import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/knowledge_item.dart';
import '../models/note_search.dart';
import '../providers/knowledge_providers.dart';
import 'widgets/category_tree.dart';
import 'widgets/item_tile.dart';
import 'widgets/note_detail_sheet.dart';

enum _NotesView { list, tree }

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  static const int _pageSize = 50;

  _NotesView _view = _NotesView.list;
  int _visible = _pageSize;
  final _scrollController = ScrollController();
  final _search = TextEditingController();
  final Set<String> _tags = {};

  bool get _filtering => _search.text.trim().isNotEmpty || _tags.isNotEmpty;

  /// The notes to show: everything, or the search results.
  List<KnowledgeItem> _notes() {
    final all = ref.watch(notesSortedProvider);
    return _filtering ? searchNotes(all, _search.text, tags: _tags) : all;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      final total = ref.read(notesSortedProvider).length;
      if (_visible < total) {
        setState(() => _visible = (_visible + _pageSize).clamp(0, total));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.navNotes),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(tags.isEmpty ? 64 : 108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() => _visible = _pageSize),
                        decoration: InputDecoration(
                          hintText: context.s.searchNotes,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.s.clear,
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(_search.clear),
                                ),
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<_NotesView>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: _NotesView.list,
                          tooltip: context.s.viewList,
                          icon: const Icon(Icons.view_list),
                        ),
                        ButtonSegment(
                          value: _NotesView.tree,
                          tooltip: context.s.viewTree,
                          icon: const Icon(Icons.park),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (s) => setState(() => _view = s.first),
                    ),
                  ],
                ),
                if (tags.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 6),
                      children: [
                        for (final (tag, count) in tags)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text('#$tag  $count'),
                              visualDensity: VisualDensity.compact,
                              selected: _tags.contains(tag.toLowerCase()),
                              onSelected: (on) => setState(() => on
                                  ? _tags.add(tag.toLowerCase())
                                  : _tags.remove(tag.toLowerCase())),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: switch (_view) {
        _NotesView.list => _buildList(),
        _NotesView.tree => _buildTree(),
      },
    );
  }

  Widget _buildList() {
    final notes = _notes();
    if (notes.isEmpty) {
      return _filtering ? _NoResults(query: _search.text) : const _EmptyNotes();
    }
    final count = _visible.clamp(0, notes.length);
    final hasMore = count < notes.length;
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: count + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        if (i >= count) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = notes[i];
        return ItemTile(
          item: item,
          onTap: () => showNoteDetailSheet(context, item),
        );
      },
    );
  }

  Widget _buildTree() {
    final groups = _filtering
        ? groupByCategory(_notes())
        : ref.watch(notesByCategoryProvider);
    if (groups.isEmpty) {
      return _filtering ? _NoResults(query: _search.text) : const _EmptyNotes();
    }
    final entries = groups.entries.toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _TreeLegend(),
        for (final entry in entries)
          CategoryTree(
            category: entry.key,
            notes: entry.value,
            onLeafTap: (item) => showNoteDetailSheet(context, item),
          ),
      ],
    );
  }
}

class _TreeLegend extends StatelessWidget {
  const _TreeLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          dot(summerLeafColor, context.s.legendLearned),
          dot(autumnLeafColor, context.s.legendNeedsTraining),
        ],
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(context.s.noNotes),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(context.s.noResults(query.trim()), textAlign: TextAlign.center),
      ),
    );
  }
}
