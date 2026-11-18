import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../llm/llm_providers.dart';
import '../models/highlights.dart';
import '../models/knowledge_item.dart';
import '../providers/knowledge_providers.dart';
import 'bulk_add_screen.dart';
import 'widgets/image_picking.dart';
import 'widgets/category_field.dart';
import 'widgets/format_bar.dart';
import 'widgets/markable_text.dart';
import 'widgets/voice_input.dart';
import 'theme.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({
    super.key,
    this.initialFront,
    this.initialBack,
    this.initialCategory,
    this.initialTopic,
  });

  /// Prefilled text, e.g. shared from another app.
  final String? initialFront;
  final String? initialBack;

  /// Prefilled place, when adding from a category or topic.
  final String? initialCategory;
  final String? initialTopic;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _frontController = HighlightingController()
    ..text = widget.initialFront ?? '';
  late final _backController = HighlightingController()
    ..text = widget.initialBack ?? '';
  late final _categoryController = TextEditingController(text: widget.initialCategory);
  late final _topicController = TextEditingController(text: widget.initialTopic);
  final _tagsController = TextEditingController();
  KnowledgeType _type = KnowledgeType.concept;
  bool _saving = false;
  bool _aiBusy = false;
  Uint8List? _imageBytes;

  /// Key ideas marked while writing (select text → Highlight).
  List<String> _highlights = const [];

  void _setHighlights(List<String> highlights) {
    if (highlights.length > KnowledgeItem.maxHighlights) {
      _showError(context.s.tooManyHighlights);
      return;
    }
    setState(() {
      _highlights = highlights;
      _frontController.highlights = highlights;
      _backController.highlights = highlights;
    });
  }

  KnowledgeItem _draft() {
    final now = DateTime.now();
    final back = _backController.text.trim();
    return KnowledgeItem(
      id: '',
      front: _frontController.text.trim(),
      back: back.isEmpty ? null : back,
      type: _type,
      createdAt: now,
      dueDate: now,
    );
  }

  Future<void> _suggestKeyIdeas() async {
    final strings = context.s;
    final llm = ref.read(llmProvider);
    if (llm == null || _frontController.text.trim().isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final suggested = await llm.suggestHighlights(_draft());
      var next = _highlights;
      for (final phrase in suggested) {
        final grown = addPhrase(next, phrase);
        if (grown.length > KnowledgeItem.maxHighlights) break;
        next = grown;
      }
      if (!mounted) return;
      if (next.length == _highlights.length) _showError(strings.noNewKeyIdeas);
      _setHighlights(next);
    } catch (e) {
      _showError(strings.couldNotSuggest(e));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Widget _highlightMenu(
          BuildContext context, EditableTextState state, TextEditingController c) =>
      highlightContextMenu(context, state,
          text: c.text, highlights: _highlights, onChanged: _setHighlights);

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _categoryController.dispose();
    _topicController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _expandWithAi() async {
    final strings = context.s;
    final llm = ref.read(llmProvider);
    if (llm == null) return;
    final front = _frontController.text.trim();
    if (front.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final now = DateTime.now();
      final probe = KnowledgeItem(
        id: '',
        front: front,
        back: _backController.text.trim().isEmpty ? null : _backController.text.trim(),
        type: _type,
        createdAt: now,
        dueDate: now,
      );
      // Only the answer is generated here; the practice quiz is batched in
      // the background after saving (see QuizPrep), saving a request.
      final answer = await llm.expandNote(probe);
      if (mounted) _backController.text = answer;
    } catch (e) {
      _showError(strings.couldNotGenerate(e));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _suggestCategory() async {
    final strings = context.s;
    final llm = ref.read(llmProvider);
    if (llm == null) return;
    final front = _frontController.text.trim();
    if (front.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final cat = await llm.suggestCategory(
        front,
        _backController.text.trim().isEmpty ? null : _backController.text.trim(),
      );
      if (mounted) _categoryController.text = cat;
    } catch (e) {
      _showError(strings.couldNotSuggest(e));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(knowledgeListProvider.notifier).addItem(
          front: _frontController.text,
          back: _backController.text,
          type: _type,
          category: _categoryController.text,
          topic: _topicController.text,
          imageBytes: _imageBytes,
          highlights: _highlights,
          tags: KnowledgeItem.parseTags(_tagsController.text),
        );
    if (mounted) Navigator.of(context).pop();
  }

  /// Many notes at once replace this single one: go there and close this.
  Future<void> _openBulk(BulkSource source) async {
    final navigator = Navigator.of(context);
    await navigator.pushReplacement(MaterialPageRoute(
      builder: (_) => BulkAddScreen(
        source: source,
        initialText: source == BulkSource.text && _backController.text.isNotEmpty
            ? _backController.text
            : null,
      ),
    ));
  }

  Future<void> _pickImage() async {
    final bytes = await pickImageBytes(context);
    if (bytes != null && mounted) setState(() => _imageBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final aiAttached = ref.watch(llmProvider) != null;
    return Scaffold(
      appBar: AppBar(title: Text(context.s.captureTitle)),
      body: Form(
        key: _formKey,
        child: ReadableBuilder(builder: (context, gutter) => ListView(
          padding: const EdgeInsets.all(16) + gutter,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(context.s.photoToNotes),
                  onPressed: () => _openBulk(BulkSource.photo),
                ),
                ActionChip(
                  avatar: const Icon(Icons.content_paste, size: 18),
                  label: Text(context.s.pasteAndSplit),
                  onPressed: () => _openBulk(BulkSource.text),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(context.s.whatKind,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
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
            const SizedBox(height: 20),
            TextFormField(
              controller: _frontController,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              contextMenuBuilder: (context, state) =>
                  _highlightMenu(context, state, _frontController),
              decoration: InputDecoration(
                labelText: context.s.prompt,
                hintText:
                    context.s.promptHint,
                suffixIcon: VoiceButton(controller: _frontController),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.s.promptRequired : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _backController,
              minLines: 2,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              contextMenuBuilder: (context, state) =>
                  _highlightMenu(context, state, _backController),
              decoration: InputDecoration(
                labelText: context.s.answerOptional,
                hintText: context.s.answerHint,
                suffixIcon: VoiceButton(controller: _backController),
              ),
            ),
            const SizedBox(height: 8),
            FormatBar(controller: _backController),
            if (aiAttached) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _aiBusy ? null : _expandWithAi,
                  icon: _aiBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(context.s.generateAnswer),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _KeyIdeas(
              highlights: _highlights,
              onRemove: (h) =>
                  _setHighlights([for (final x in _highlights) if (x != h) x]),
              onSuggest: aiAttached && !_aiBusy ? _suggestKeyIdeas : null,
            ),
            const SizedBox(height: 16),
            CategoryField(
              controller: _categoryController,
              trailing: aiAttached
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton(
                        tooltip: context.s.suggestCategory,
                        onPressed: _aiBusy ? null : _suggestCategory,
                        icon: const Icon(Icons.auto_awesome),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            TopicField(controller: _topicController, category: _categoryController),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tagsController,
              decoration: InputDecoration(
                labelText: context.s.tagsField,
                hintText: context.s.tagsHint,
                prefixIcon: const Icon(Icons.sell_outlined),
              ),
            ),
            const SizedBox(height: 16),
            if (_imageBytes != null) ...[
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _imageBytes!,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _imageBytes = null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(_imageBytes == null ? context.s.addImage : context.s.replaceImage),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(context.s.save),
            ),
          ],
        ),
      )),
    );
  }
}

/// The marked key ideas while writing a note, with how to mark them and the
/// AI's suggestions.
class _KeyIdeas extends StatelessWidget {
  const _KeyIdeas({required this.highlights, required this.onRemove, this.onSuggest});

  final List<String> highlights;
  final ValueChanged<String> onRemove;
  final VoidCallback? onSuggest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: markerColor(context).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.border_color, size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.s.captureMarkerHint,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final h in highlights)
                  InputChip(
                    label: Text(h),
                    backgroundColor: markerColor(context),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => onRemove(h),
                  ),
              ],
            ),
          ],
          if (onSuggest != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onSuggest,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(context.s.suggestKeyIdeas),
              ),
            ),
        ],
      ),
    );
  }
}
