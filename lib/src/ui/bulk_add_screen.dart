
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/split_notes.dart';
import '../l10n/app_strings.dart';
import '../llm/llm_provider.dart';
import '../llm/llm_providers.dart';
import '../llm/quiz_prep.dart';
import '../providers/knowledge_providers.dart';
import 'widgets/category_field.dart';
import 'widgets/image_picking.dart';
import 'widgets/item_tile.dart';

/// Where the notes come from.
enum BulkSource { text, photo, import }

/// Makes many notes at once: from a photo of a page, slide or whiteboard
/// (read by the AI), or from pasted text (split by the AI, or line by line
/// without one). The student ticks the proposed notes to keep.
class BulkAddScreen extends ConsumerStatefulWidget {
  const BulkAddScreen({
    super.key,
    required this.source,
    this.initialText,
    this.initialImage,
    this.initialDrafts,
  });

  final BulkSource source;
  final String? initialText;
  final Uint8List? initialImage;

  /// Notes already read from a file (Anki, Quizlet), shown for picking.
  final List<NoteDraft>? initialDrafts;

  @override
  ConsumerState<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends ConsumerState<BulkAddScreen> {
  late final _text = TextEditingController(text: widget.initialText ?? '');
  final _category = TextEditingController();
  final _topic = TextEditingController();
  late Uint8List? _image = widget.initialImage;
  List<NoteDraft>? _drafts;
  final Set<int> _keep = {};
  bool _busy = false;
  String? _message;

  bool get _isPhoto => widget.source == BulkSource.photo;
  bool get _isImport => widget.source == BulkSource.import;

  @override
  void initState() {
    super.initState();
    final drafts = widget.initialDrafts;
    if (drafts != null) {
      // Imported notes keep their own decks as categories.
      _drafts = drafts;
      _keep.addAll(List.generate(drafts.length, (i) => i));
    }
    if (_isPhoto && _image == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickPhoto());
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _category.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickImageBytes(context);
    if (bytes != null && mounted) {
      setState(() {
        _image = bytes;
        _message = null;
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    setState(() => _text.text = _text.text.isEmpty ? text : '${_text.text}\n$text');
  }

  void _show(List<NoteDraft> drafts) {
    final strings = context.s;
    // Prefill the shared category with the AI's most common one.
    final counts = <String, int>{};
    for (final d in drafts) {
      if (d.category != null) counts[d.category!] = (counts[d.category!] ?? 0) + 1;
    }
    final common = counts.entries.isEmpty
        ? null
        : (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
    setState(() {
      _drafts = drafts;
      _keep
        ..clear()
        ..addAll(List.generate(drafts.length, (i) => i));
      if (common != null && _category.text.isEmpty) _category.text = common;
      _message = drafts.isEmpty ? strings.noNotesFound : null;
      if (drafts.isEmpty) _drafts = null;
    });
  }

  Future<void> _make({bool useAi = true}) async {
    final strings = context.s;
    final llm = useAi ? ref.read(llmProvider) : null;
    if (!_isPhoto && llm == null) {
      _show(splitLocally(_text.text));
      return;
    }
    if (llm == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final drafts = _isPhoto
          ? await llm.notesFromImage(Attachment.image(_image!))
          : await llm.notesFromText(_text.text);
      if (mounted) _show(drafts);
    } on LlmException catch (e) {
      if (mounted) {
        ref.read(quizPrepProvider.notifier).reportError(e);
        setState(() => _message = strings.aiFailure(e.kind, e.message));
      }
    } catch (e) {
      if (mounted) setState(() => _message = strings.couldNotGenerate(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(int index) async {
    final draft = _drafts![index];
    final front = TextEditingController(text: draft.front);
    final back = TextEditingController(text: draft.back ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.s.edit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: front,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: context.s.prompt),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: back,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                  labelText: context.s.answerDetails),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.s.save)),
        ],
      ),
    );
    if (saved == true && front.text.trim().isNotEmpty && mounted) {
      setState(() => _drafts![index] =
          draft.copyWith(front: front.text.trim(), back: back.text.trim()));
    }
    front.dispose();
    back.dispose();
  }

  Future<void> _save() async {
    final strings = context.s;
    final messenger = ScaffoldMessenger.of(context);
    final chosen = [
      for (var i = 0; i < _drafts!.length; i++)
        if (_keep.contains(i)) _drafts![i],
    ];
    setState(() => _busy = true);
    await ref
        .read(knowledgeListProvider.notifier)
        .addDrafts(chosen,
            category: _category.text, topic: _topic.text, onlyMissing: _isImport);
    if (!mounted) return;
    Navigator.of(context).pop(chosen.length);
    messenger.showSnackBar(SnackBar(content: Text(strings.savedNotes(chosen.length))));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final drafts = _drafts;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.source) {
          BulkSource.photo => strings.photoToNotes,
          BulkSource.text => strings.pasteAndSplit,
          BulkSource.import => strings.importTitle,
        }),
        actions: [
          if (drafts != null && !_isImport)
            TextButton(
              onPressed: _busy ? null : () => setState(() => _drafts = null),
              child: Text(strings.startOver),
            ),
        ],
      ),
      body: drafts == null ? _buildInput() : _buildDrafts(drafts),
      bottomNavigationBar: drafts == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _busy || _keep.isEmpty ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(strings.saveNotes(_keep.length)),
                ),
              ),
            ),
    );
  }

  Widget _buildInput() {
    final strings = context.s;
    final theme = Theme.of(context);
    final llm = ref.watch(llmProvider);
    final canAi = llm != null && (!_isPhoto || llm.canReadImages);
    final ready = _isPhoto ? _image != null : _text.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isPhoto) ...[
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(_image!, height: 320, fit: BoxFit.contain),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_image == null ? strings.choosePhoto : strings.anotherPhoto),
          ),
          if (!canAi)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(strings.needVisionAi,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            ),
        ] else ...[
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 18,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: strings.pasteHere,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
              label: Text(strings.pasteFromClipboard),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_busy)
          Column(
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_isPhoto ? strings.readingPhoto : strings.makingNotes),
            ],
          )
        else ...[
          if (canAi || !_isPhoto)
            FilledButton.icon(
              onPressed: ready ? () => _make() : null,
              icon: Icon(canAi ? Icons.auto_awesome : Icons.call_split),
              label: Text(canAi ? strings.makeNotesAi : strings.splitByLines),
            ),
          if (!_isPhoto && canAi)
            TextButton.icon(
              onPressed: ready ? () => _make(useAi: false) : null,
              icon: const Icon(Icons.call_split),
              label: Text(strings.splitByLines),
            ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
      ],
    );
  }

  Widget _buildDrafts(List<NoteDraft> drafts) {
    final strings = context.s;
    final theme = Theme.of(context);
    final all = _keep.length == drafts.length;
    // Built lazily: an imported deck can hold thousands of notes.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: drafts.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(strings.notesFound(drafts.length),
                      style: theme.textTheme.bodyMedium),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    all
                        ? _keep.clear()
                        : _keep.addAll(List.generate(drafts.length, (i) => i));
                  }),
                  child: Text(all ? strings.selectNone : strings.selectAll),
                ),
              ],
            ),
          );
        }
        if (i == drafts.length + 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                CategoryField(
                  controller: _category,
                  labelText: _isImport ? strings.categoryForMissing : strings.categoryForAll,
                ),
                const SizedBox(height: 12),
                TopicField(controller: _topic, category: _category),
              ],
            ),
          );
        }
        final index = i - 1;
        final draft = drafts[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _edit(index),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _keep.contains(index),
                    onChanged: (v) => setState(
                        () => v == true ? _keep.add(index) : _keep.remove(index)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text(draft.front,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall),
                        if (draft.back != null) ...[
                          const SizedBox(height: 4),
                          Text(draft.back!,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium),
                        ],
                        if (_isImport && draft.category != null) ...[
                          const SizedBox(height: 4),
                          Text(draft.category!,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.primary)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TypeChip(type: draft.type),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens [BulkAddScreen]; a common entry point for capture and sharing.
Future<void> openBulkAdd(BuildContext context, BulkSource source,
    {String? text, Uint8List? image}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        BulkAddScreen(source: source, initialText: text, initialImage: image),
  ));
}
