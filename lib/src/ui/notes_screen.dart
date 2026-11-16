import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/knowledge_item.dart';
import '../models/note_search.dart';
import '../providers/knowledge_providers.dart';
import '../providers/navigation.dart';
import 'widgets/category_field.dart';
import 'widgets/category_tree.dart';
import 'widgets/item_tile.dart';
import 'widgets/note_detail_sheet.dart';
import 'widgets/undo_delete.dart';

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
  final _searchFocus = FocusNode();

  /// On wide screens, the note open beside the list.
  String? _openId;
  final Set<String> _tags = {};

  /// Chosen categories ('' stands for notes without one) and topics; none
  /// is all.
  final Set<String> _categories = {};

  /// Notes chosen to move or delete together (long-press starts choosing).
  final Set<String> _selected = {};

  void _toggleSelected(String id) => setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _moveSelected() async {
    final strings = context.s;
    // Notes from one category start there, so only the topic needs picking.
    final places = {
      for (final n in ref.read(notesSortedProvider))
        if (_selected.contains(n.id)) n.category,
    };
    final category = TextEditingController(
        text: places.length == 1 ? places.first ?? '' : '');
    final topic = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.moveNotes(_selected.length)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategoryField(controller: category, labelText: strings.category, showRecent: false),
              const SizedBox(height: 12),
              TopicField(controller: topic, category: category),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.move)),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(knowledgeListProvider.notifier)
          .moveNotes({..._selected}, category.text, topic.text);
      if (mounted) setState(_selected.clear);
    }
    category.dispose();
    topic.dispose();
  }

  Future<void> _deleteSelected() async {
    final strings = context.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteNotes(_selected.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(knowledgeListProvider.notifier);
    final deleted = await store.deleteMany({..._selected});
    if (mounted) setState(_selected.clear);
    showUndoDelete(messenger, strings, store, deleted);
  }

  bool get _filtering =>
      _search.text.trim().isNotEmpty || _tags.isNotEmpty || _categories.isNotEmpty;

  /// The notes to show: everything, or the search results.
  List<KnowledgeItem> _notes() {
    final all = ref.watch(notesSortedProvider);
    return _filtering
        ? searchNotes(all, _search.text, tags: _tags, categories: _categories)
        : all;
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
    _searchFocus.dispose();
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

  void _toggleCategory(String category, bool on) => setState(() {
        on ? _categories.add(category) : _categories.remove(category);
        _visible = _pageSize;
      });

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    // "See notes" from a category or topic elsewhere.
    ref.listen(notesFilterRequestProvider, (_, request) {
      if (request == null) return;
      setState(() {
        _categories
          ..clear()
          ..addAll(request);
        _tags.clear();
        _search.clear();
        _view = _NotesView.list;
        _visible = _pageSize;
      });
      ref.read(notesFilterRequestProvider.notifier).clear();
    });
    ref.listen(notesSearchFocusProvider, (_, _) => _searchFocus.requestFocus());
    final tags = ref.watch(tagsProvider);
    final groups = ref.watch(notesByCategoryProvider);
    final total = ref.watch(notesSortedProvider).length;
    final showFilters = tags.isNotEmpty || groups.length > 1;
    return Scaffold(
      appBar: _selected.isNotEmpty
          ? AppBar(
              leading: IconButton(
                tooltip: strings.cancel,
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              ),
              title: Text(strings.selectedCount(_selected.length)),
              actions: [
                IconButton(
                  tooltip: strings.selectAll,
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(() => _selected.addAll(_notes().map((n) => n.id))),
                ),
                IconButton(
                  tooltip: strings.moveTo,
                  icon: const Icon(Icons.drive_file_move_outlined),
                  onPressed: _moveSelected,
                ),
                IconButton(
                  tooltip: strings.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteSelected,
                ),
                const SizedBox(width: 4),
              ],
            )
          : AppBar(
        title: Text(strings.navNotes),
        actions: [
          IconButton(
            tooltip: _view == _NotesView.list ? strings.viewTree : strings.viewList,
            icon: Icon(_view == _NotesView.list ? Icons.park_outlined : Icons.view_agenda_outlined),
            onPressed: () => setState(() => _view =
                _view == _NotesView.list ? _NotesView.tree : _NotesView.list),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(showFilters ? 112 : 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() => _visible = _pageSize),
                  decoration: InputDecoration(
                    hintText: strings.searchNotesCount(total),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clear,
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_search.clear),
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary, width: 1.6)),
                  ),
                ),
                if (showFilters)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 8),
                      children: [
                        if (groups.length > 1) ...[
                          _CategoryFilter(
                            groups: groups,
                            topics: ref.watch(topicInfoProvider),
                            selected: _categories,
                            onToggle: _toggleCategory,
                            onClear: () => setState(_categories.clear),
                          ),
                          const SizedBox(width: 6),
                        ],
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
        _NotesView.list => LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < _twoPaneWidth) return _buildList(wide: false);
              final open = _openId == null
                  ? null
                  : ref.watch(notesSortedProvider).where((n) => n.id == _openId).firstOrNull;
              return Row(
                children: [
                  SizedBox(width: 420, child: _buildList(wide: true)),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: open == null
                        ? _NoNoteOpen()
                        : Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: NoteDetailView(
                                key: ValueKey(open.id),
                                item: open,
                                embedded: true,
                                onDeleted: () => setState(() => _openId = null),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        _NotesView.tree => _buildTree(),
      },
    );
  }

  /// Wider than this, the open note shows beside the list.
  static const double _twoPaneWidth = 900;

  Widget _buildList({required bool wide}) {
    final notes = _notes();
    if (notes.isEmpty) {
      return _filtering ? _NoResults(query: _search.text) : const _EmptyNotes();
    }
    final count = _visible.clamp(0, notes.length);
    final header = _filtering ? 1 : 0;
    final hasMore = count < notes.length;
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: header + count + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i < header) {
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(context.s.foundNotes(notes.length),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          );
        }
        i -= header;
        if (i >= count) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = notes[i];
        final choosing = _selected.isNotEmpty;
        return ItemTile(
          item: item,
          showCategory: _categories.length != 1,
          selected: choosing ? _selected.contains(item.id) : null,
          onLongPress: () => _toggleSelected(item.id),
          onTap: choosing
              ? () => _toggleSelected(item.id)
              : wide
                  ? () => setState(() => _openId = item.id)
                  : () => showNoteDetailSheet(context, item),
          selectedInPane: wide && _openId == item.id,
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

/// "Category ▾": a menu to show only some categories' notes.
class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.groups,
    required this.topics,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  final Map<String, List<KnowledgeItem>> groups;
  final Map<String, List<CategoryInfo>> topics;

  /// Category names and [topicKey]s.
  final Set<String> selected;
  final void Function(String category, bool on) onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    String key(String group) => group == kUngroupedCategory ? '' : group;
    final label = switch (selected.length) {
      0 => strings.allCategories,
      1 => selected.first.isEmpty
          ? strings.ungrouped
          : selected.first.replaceAll('\u001f', ' › '),
      final n => strings.categoriesChosen(n),
    };
    return MenuAnchor(
      menuChildren: [
        for (final e in groups.entries) ...[
          CheckboxMenuButton(
            value: selected.contains(key(e.key)),
            closeOnActivate: false,
            onChanged: (on) => onToggle(key(e.key), on ?? false),
            trailingIcon: Text('${e.value.length}',
                style: Theme.of(context).textTheme.labelMedium),
            child: Text(categoryDisplayName(context, e.key)),
          ),
          for (final t in topics[e.key] ?? const <CategoryInfo>[])
            CheckboxMenuButton(
              value: selected.contains(topicKey(e.key, t.name)),
              closeOnActivate: false,
              onChanged: (on) => onToggle(topicKey(e.key, t.name), on ?? false),
              trailingIcon: Text('${t.count}',
                  style: Theme.of(context).textTheme.labelMedium),
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(t.name),
              ),
            ),
        ],
        if (selected.isNotEmpty) ...[
          const Divider(height: 8),
          MenuItemButton(
            leadingIcon: const Icon(Icons.clear_all),
            onPressed: onClear,
            child: Text(strings.showAll),
          ),
        ],
      ],
      builder: (context, menu, _) => FilterChip(
        avatar: Icon(Icons.folder_outlined,
            size: 18,
            color: selected.isEmpty ? null : Theme.of(context).colorScheme.onSecondaryContainer),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label), const Icon(Icons.arrow_drop_down, size: 18)],
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selected: selected.isNotEmpty,
        onSelected: (_) => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class _NoNoteOpen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(context.s.pickANote, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
