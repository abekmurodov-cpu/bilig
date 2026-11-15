import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../llm/llm_provider.dart';
import '../../llm/llm_providers.dart';
import '../../llm/quiz_prep.dart';
import '../../models/knowledge_item.dart';
import '../../providers/knowledge_providers.dart';
import '../../models/highlights.dart';
import 'category_field.dart';
import 'image_picking.dart';
import 'item_tile.dart';
import 'markable_text.dart';
import 'note_image.dart';

/// Bottom sheet showing a note's details with quick edit + delete, the
/// marker for key ideas, and the note's practice questions. Opened from the
/// notes list and from tree leaves.
Future<void> showNoteDetailSheet(BuildContext context, KnowledgeItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NoteDetailSheet(item: item),
  );
}

class _NoteDetailSheet extends ConsumerStatefulWidget {
  const _NoteDetailSheet({required this.item});

  final KnowledgeItem item;

  @override
  ConsumerState<_NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends ConsumerState<_NoteDetailSheet> {
  late final TextEditingController _front =
      TextEditingController(text: widget.item.front);
  late final TextEditingController _back =
      TextEditingController(text: widget.item.back ?? '');
  late final TextEditingController _category =
      TextEditingController(text: widget.item.category ?? '');
  late final TextEditingController _topic =
      TextEditingController(text: widget.item.topic ?? '');
  late final TextEditingController _tags =
      TextEditingController(text: widget.item.tags.join(', '));
  late KnowledgeType _type = widget.item.type;
  bool _editing = false;

  /// Highlights being marked with the marker; saved together on "Done" (or
  /// when the sheet closes) so the AI rewrites its questions once.
  List<String>? _marking;
  String? _markMessage;
  late final KnowledgeListNotifier _notes;

  @override
  void initState() {
    super.initState();
    _notes = ref.read(knowledgeListProvider.notifier);
  }

  /// The latest stored copy: questions and highlights change while open.
  KnowledgeItem get _item {
    final items = ref.watch(knowledgeListProvider).asData?.value ?? const [];
    for (final i in items) {
      if (i.id == widget.item.id) return i;
    }
    return widget.item;
  }

  @override
  void dispose() {
    final pending = _marking;
    if (pending != null) _commitHighlights(_latest, pending);
    _front.dispose();
    _back.dispose();
    _category.dispose();
    _topic.dispose();
    _tags.dispose();
    super.dispose();
  }

  /// The copy shown in the last build, for use outside build.
  late KnowledgeItem _latest = widget.item;

  Future<void> _commitHighlights(KnowledgeItem item, List<String> highlights) {
    if (_same(item.highlights, highlights)) {
      return Future.value();
    }
    return _notes.setHighlights(item, highlights);
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  /// Applies a marker change, refusing to go past the limit.
  bool _withinLimit(List<String> highlights) {
    if (highlights.length <= KnowledgeItem.maxHighlights) return true;
    setState(() => _markMessage = context.s.tooManyHighlights);
    return false;
  }

  void _onMarked(List<String> highlights) {
    if (!_withinLimit(highlights)) return;
    setState(() {
      _marking = highlights;
      _markMessage = null;
    });
  }

  /// A highlight added or removed from the selection menu is saved at once.
  Future<void> _onSelectionMarked(KnowledgeItem item, List<String> highlights) async {
    if (!_withinLimit(highlights)) return;
    final strings = context.s;
    final aiAttached = ref.read(llmProvider) != null;
    await _commitHighlights(item, highlights);
    if (mounted) {
      setState(() => _markMessage = aiAttached ? strings.highlightsSaved : null);
    }
  }

  bool _suggesting = false;

  /// Asks the AI for the note's key ideas and marks them in the draft; the
  /// student keeps or untaps them before "Done".
  Future<void> _suggest(KnowledgeItem item) async {
    final strings = context.s;
    final llm = ref.read(llmProvider);
    if (llm == null) return;
    setState(() {
      _suggesting = true;
      _markMessage = null;
    });
    String message;
    try {
      final suggested = await llm.suggestHighlights(item);
      var draft = _marking ?? [...item.highlights];
      var added = 0;
      for (final phrase in suggested) {
        final next = addPhrase(draft, phrase);
        if (next.length > KnowledgeItem.maxHighlights) break;
        if (!_same(next, draft)) added++;
        draft = next;
      }
      if (mounted) setState(() => _marking = draft);
      message = added == 0 ? strings.noNewKeyIdeas : strings.keyIdeasSuggested(added);
    } on LlmException catch (e) {
      if (mounted) ref.read(quizPrepProvider.notifier).reportError(e);
      message = strings.aiFailure(e.kind, e.message);
    } catch (_) {
      message = strings.noNewKeyIdeas;
    }
    if (mounted) {
      setState(() {
        _suggesting = false;
        _markMessage = message;
      });
    }
  }

  Future<void> _toggleMarker(KnowledgeItem item) async {
    final pending = _marking;
    if (pending == null) {
      setState(() {
        _marking = [...item.highlights];
        _markMessage = null;
      });
      return;
    }
    final strings = context.s;
    final changed = !_same(item.highlights, pending);
    final aiAttached = ref.read(llmProvider) != null;
    setState(() => _marking = null);
    await _commitHighlights(item, pending);
    if (mounted && changed) {
      setState(() => _markMessage = aiAttached ? strings.highlightsSaved : null);
    }
  }

  Future<void> _save() async {
    await ref.read(knowledgeListProvider.notifier).updateItem(
          _latest,
          front: _front.text,
          back: _back.text,
          type: _type,
          category: _category.text,
          topic: _topic.text,
          tags: KnowledgeItem.parseTags(_tags.text),
        );
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _delete() async {
    await ref.read(knowledgeListProvider.notifier).delete(widget.item.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickImage() async {
    final bytes = await pickImageBytes(context);
    if (bytes == null) return;
    await ref.read(knowledgeListProvider.notifier).setImage(_latest, bytes);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    _latest = item;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
      child: _editing ? _buildEdit() : _buildView(item),
    );
  }

  Widget _buildView(KnowledgeItem item) {
    final theme = Theme.of(context);
    final marking = _marking;
    final highlights = marking ?? item.highlights;
    void onChanged(List<String> h) =>
        marking != null ? _onMarked(h) : _onSelectionMarked(item, h);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TypeChip(type: item.type),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.s.noteType(item.type).toUpperCase(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(letterSpacing: 1.2)),
            ),
            IconButton(
              // Marker-yellow, so it doesn't read as a second edit button.
              icon: Icon(Icons.border_color, color: Colors.amber.shade800),
              style: marking != null
                  ? IconButton.styleFrom(backgroundColor: markerColor(context))
                  : null,
              tooltip: context.s.marker,
              onPressed: () => _toggleMarker(item),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.s.edit,
              onPressed: marking != null
                  ? null
                  : () => setState(() => _editing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.s.delete,
              onPressed: _delete,
            ),
          ],
        ),
        if (marking != null)
          _MarkerBar(
            onDone: () => _toggleMarker(item),
            onSuggest: ref.watch(llmProvider) == null || _suggesting
                ? null
                : () => _suggest(item),
            suggesting: _suggesting,
          )
        else
          const SizedBox(height: 8),
        if (_markMessage != null) ...[
          Text(_markMessage!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 8),
        ],
        MarkableText(
          text: item.front,
          highlights: highlights,
          style: theme.textTheme.headlineSmall,
          marking: marking != null,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        NoteImage(noteId: item.id),
        const Divider(height: 28),
        if (item.hasAnswer)
          MarkableText(
            text: item.back!,
            highlights: highlights,
            style: theme.textTheme.bodyLarge,
            marking: marking != null,
            onChanged: onChanged,
          )
        else
          Text(
            context.s.noAnswerYet,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (item.category != null)
              Chip(
                avatar: const Icon(Icons.folder_outlined, size: 16),
                label: Text(item.topic == null
                    ? item.category!
                    : '${item.category!} › ${item.topic!}'),
              ),
            for (final tag in item.tags)
              Chip(
                label: Text('#$tag'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const Divider(height: 28),
        _QuestionsSection(item: item),
      ],
    );
  }

  Widget _buildEdit() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final type in KnowledgeType.values)
              ChoiceChip(
                label: Text(context.s.noteType(type)),
                selected: _type == type,
                onSelected: (_) => setState(() => _type = type),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _front,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
              labelText: context.s.prompt),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _back,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
              labelText: context.s.answerDetails),
        ),
        const SizedBox(height: 12),
        CategoryField(controller: _category, labelText: context.s.category),
        const SizedBox(height: 12),
        TopicField(controller: _topic, category: _category),
        const SizedBox(height: 12),
        TextField(
          controller: _tags,
          decoration: InputDecoration(
            labelText: context.s.tagsField,
            hintText: context.s.tagsHint,
            prefixIcon: const Icon(Icons.sell_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(_latest.hasImage ? context.s.replaceImage : context.s.addImage),
            ),
            if (_latest.hasImage) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => ref
                    .read(knowledgeListProvider.notifier)
                    .removeImage(_latest),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.s.remove),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _editing = false),
              child: Text(context.s.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: Text(context.s.save)),
          ],
        ),
      ],
    );
  }
}

/// Shown while the marker is on: what to do, and "Done".
class _MarkerBar extends StatelessWidget {
  const _MarkerBar({required this.onDone, this.onSuggest, this.suggesting = false});

  final VoidCallback onDone;

  /// Null hides the button (no AI) unless [suggesting].
  final VoidCallback? onSuggest;
  final bool suggesting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: markerColor(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              const Icon(Icons.border_color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(context.s.markerHint, style: theme.textTheme.bodySmall),
              )),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              if (onSuggest != null || suggesting)
                TextButton.icon(
                  onPressed: onSuggest,
                  icon: suggesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(context.s.suggestKeyIdeas),
                ),
              FilledButton.tonal(onPressed: onDone, child: Text(context.s.done)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The note's practice questions: each can be edited, rewritten by the AI
/// or deleted; new ones can be generated or written by hand.
class _QuestionsSection extends ConsumerStatefulWidget {
  const _QuestionsSection({required this.item});

  final KnowledgeItem item;

  @override
  ConsumerState<_QuestionsSection> createState() => _QuestionsSectionState();
}

class _QuestionsSectionState extends ConsumerState<_QuestionsSection> {
  /// Which action is running: 'more' or the index being rewritten.
  Object? _busy;
  String? _message;

  KnowledgeItem get _item => widget.item;

  Future<void> _run(Object busy, Future<String?> Function() task) async {
    final strings = context.s;
    setState(() {
      _busy = busy;
      _message = null;
    });
    String? message;
    try {
      message = await task();
    } on LlmException catch (e) {
      message = strings.aiFailure(e.kind, e.message);
    } catch (_) {
      message = strings.noNewQuestion;
    }
    if (mounted) {
      setState(() {
        _busy = null;
        _message = message;
      });
    }
  }

  void _generate(int count) {
    final strings = context.s;
    _run('more', () async {
      final added = await ref
          .read(quizPrepProvider.notifier)
          .generateMore(_item.id, count: count);
      return added == 0 ? strings.noNewQuestion : strings.questionsAdded(added);
    });
  }

  void _rewrite(int index) {
    final strings = context.s;
    _run(index, () async {
      final ok = await ref.read(quizPrepProvider.notifier).rewrite(_item.id, index);
      return ok ? null : strings.noNewQuestion;
    });
  }

  Future<void> _delete(int index) async {
    final strings = context.s;
    final wasAi = !_item.quizVariants[index].manual;
    await ref.read(knowledgeListProvider.notifier).persist(_item.removeQuiz(index));
    if (mounted) setState(() => _message = wasAi ? strings.questionRemoved : null);
  }

  Future<void> _edit({int? index}) async {
    final existing = index == null ? null : _item.quizVariants[index];
    final variant = await showDialog<QuizVariant>(
      context: context,
      builder: (_) => _QuestionDialog(item: _item, existing: existing),
    );
    if (variant == null) return;
    await ref
        .read(knowledgeListProvider.notifier)
        .persist(_item.putQuiz(variant, index: index));
    if (mounted) setState(() => _message = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.s;
    final item = _item;
    final variants = item.quizVariants;
    final aiAttached = ref.watch(llmProvider) != null;
    final full = variants.length >= KnowledgeItem.maxQuizzes;
    final busy = _busy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.questionsTitle(variants.length),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (variants.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              aiAttached && item.needsQuiz ? strings.aiWillWrite : strings.noQuestionsYet,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ),
        for (var i = 0; i < variants.length; i++)
          _QuestionTile(
            item: item,
            variant: variants[i],
            next: variants.length > 1 && i == item.activeQuizIndex,
            rewriting: _busy == i,
            onEdit: busy ? null : () => _edit(index: i),
            onRewrite: busy || !aiAttached ? null : () => _rewrite(i),
            onDelete: busy ? null : () => _delete(i),
          ),
        if (_busy == 'more')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (aiAttached) ...[
              FilledButton.tonalIcon(
                onPressed: busy || full ? null : () => _generate(1),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('+ ${strings.addOneQuestion}'),
              ),
              OutlinedButton.icon(
                onPressed: busy || full ? null : () => _generate(3),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('+ ${strings.addThreeQuestions}'),
              ),
            ],
            TextButton.icon(
              onPressed: busy || full ? null : () => _edit(),
              icon: const Icon(Icons.edit_note),
              label: Text(strings.writeOwn),
            ),
          ],
        ),
        if (full || !aiAttached || _message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _message ?? (full ? strings.questionLimit : strings.connectAiToGenerate),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: _message != null ? theme.colorScheme.primary : Colors.grey),
            ),
          ),
      ],
    );
  }
}

Widget _optionLine(IconData icon, Color color, String text, TextStyle? style) =>
    Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 4),
            child: Icon(icon, size: 14, color: color),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.item,
    required this.variant,
    required this.next,
    required this.rewriting,
    required this.onEdit,
    required this.onRewrite,
    required this.onDelete,
  });

  final KnowledgeItem item;
  final QuizVariant variant;
  final bool next;
  final bool rewriting;
  final VoidCallback? onEdit;
  final VoidCallback? onRewrite;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.s;
    final small = theme.textTheme.bodySmall;
    Widget tag(String label) => Container(
          margin: const EdgeInsets.only(right: 6, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: theme.textTheme.labelSmall),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (next || variant.manual)
                  Row(children: [
                    if (next) tag(strings.askedNext),
                    if (variant.manual) tag(strings.yourQuestion),
                  ]),
                Text(variant.question ?? item.front,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                _optionLine(Icons.check, Colors.green.shade700, variant.answer,
                    small?.copyWith(color: Colors.green.shade700)),
                if (variant.distractors.isNotEmpty)
                  _optionLine(Icons.close, Colors.grey,
                      variant.distractors.join('  ·  '),
                      small?.copyWith(color: Colors.grey)),
                if (rewriting)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: onEdit != null,
            onSelected: (action) => switch (action) {
              'edit' => onEdit?.call(),
              'rewrite' => onRewrite?.call(),
              _ => onDelete?.call(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(strings.edit)),
              ),
              if (onRewrite != null)
                PopupMenuItem(
                  value: 'rewrite',
                  child: ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: Text(strings.rewriteWithAi)),
                ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(strings.delete)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Writing or editing a question by hand. Returns the student's question.
class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.item, this.existing});

  final KnowledgeItem item;
  final QuizVariant? existing;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late final _question = TextEditingController(
      text: widget.existing?.question ??
          (widget.existing != null || widget.item.type == KnowledgeType.question
              ? widget.item.front
              : ''));
  late final _answer = TextEditingController(text: widget.existing?.answer ?? '');
  late final _wrong = TextEditingController(
      text: widget.existing?.distractors.join('\n') ?? '');

  @override
  void initState() {
    super.initState();
    _question.addListener(_changed);
    _answer.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _wrong.dispose();
    super.dispose();
  }

  bool get _valid =>
      _question.text.trim().isNotEmpty && _answer.text.trim().isNotEmpty;

  void _save() {
    final question = _question.text.trim();
    final answer = _answer.text.trim();
    final wrong = {
      for (final line in _wrong.text.split('\n'))
        if (line.trim().isNotEmpty && line.trim() != answer) line.trim(),
    }.toList();
    Navigator.of(context).pop(QuizVariant(
      // The note's own wording is stored as "no separate question".
      question: question == widget.item.front.trim() ? null : question,
      answer: answer,
      distractors: wrong,
      manual: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    return AlertDialog(
      title: Text(widget.existing == null ? strings.writeOwn : strings.edit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _question,
              autofocus: widget.existing == null,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: strings.questionField),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answer,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: strings.correctAnswerField),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wrong,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.wrongOptionsField,
                helperText: strings.wrongOptionsHint,
                helperMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: Text(strings.cancel)),
        FilledButton(onPressed: _valid ? _save : null, child: Text(strings.save)),
      ],
    );
  }
}
