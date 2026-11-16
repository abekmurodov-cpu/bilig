import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/knowledge_item.dart';
import '../practice/practice_models.dart';
import '../providers/knowledge_providers.dart';
import 'theme.dart';
import 'widgets/category_sheet.dart' show studyOrder;
import 'widgets/category_tree.dart';
import 'widgets/file_io.dart';
import 'widgets/item_tile.dart' show TypeChip;
import 'widgets/note_detail_sheet.dart';
import 'widgets/note_image.dart';
import 'widgets/note_text.dart';
import 'widgets/study_cards.dart' show startSession;

/// A category (or one topic of it) as one page of notes to read through:
/// a title page, contents, numbered sections per topic, and every note set
/// like a well-kept notebook, formatting, formulas and highlights included.
class NotePaperScreen extends ConsumerStatefulWidget {
  const NotePaperScreen({super.key, required this.category, this.topic});

  final String category;
  final String? topic;

  @override
  ConsumerState<NotePaperScreen> createState() => _NotePaperScreenState();
}

/// The paper's own colours: warm in light mode, inky in dark.
class _Paper {
  _Paper(BuildContext context) : dark = Theme.of(context).brightness == Brightness.dark;

  final bool dark;
  Color get page => dark ? const Color(0xFF1C1A17) : const Color(0xFFFBF7EF);
  Color get desk => dark ? const Color(0xFF121110) : const Color(0xFFEFE9DD);
  Color get ink => dark ? const Color(0xFFEDE6D8) : const Color(0xFF2B2620);
  Color get faded => dark ? const Color(0xFFA79F90) : const Color(0xFF7A6F60);
  Color get dots => (dark ? Colors.white : const Color(0xFF6B5A3E)).withValues(alpha: 0.07);
  Color get accent => dark ? const Color(0xFFE9A15B) : const Color(0xFFB4532A);
}

class _NotePaperScreenState extends ConsumerState<NotePaperScreen> {
  final Map<String, GlobalKey> _sectionKeys = {};

  /// Sections in order: each topic (most notes first), then notes without a
  /// topic. Within a section, oldest first, as they were written.
  List<(String?, List<KnowledgeItem>)> _sections(List<KnowledgeItem> notes) {
    final byTopic = <String?, List<KnowledgeItem>>{};
    for (final n in notes) {
      (byTopic[n.topic] ??= []).add(n);
    }
    for (final list in byTopic.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final topics = byTopic.keys.whereType<String>().toList()
      ..sort((a, b) => byTopic[b]!.length.compareTo(byTopic[a]!.length));
    return [
      for (final t in topics) (t, byTopic[t]!),
      if (byTopic.containsKey(null)) (null, byTopic[null]!),
    ];
  }

  String _markdown(String title, List<(String?, List<KnowledgeItem>)> sections) {
    final strings = context.s;
    final out = StringBuffer('# $title\n\n');
    for (final (topic, notes) in sections) {
      if (sections.length > 1 || topic != null) {
        out.writeln('## ${topic ?? strings.otherNotes}\n');
      }
      for (final n in notes) {
        out.writeln('### ${n.front.trim()}\n');
        final back = n.back?.trim();
        if (back != null && back.isNotEmpty) {
          out.writeln(n.type == KnowledgeType.code && !back.startsWith('```')
              ? '```\n$back\n```\n'
              : '$back\n');
        }
      }
    }
    return out.toString();
  }

  Future<void> _export(String title, List<(String?, List<KnowledgeItem>)> sections) async {
    final bytes = Uint8List.fromList(utf8.encode(_markdown(title, sections)));
    final safe = title.replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '').trim();
    await saveOrShareFile(bytes, '${safe.isEmpty ? 'notes' : safe}.md', mimeType: 'text/markdown');
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final paper = _Paper(context);
    final all = ref.watch(notesByCategoryProvider)[widget.category] ?? const <KnowledgeItem>[];
    final notes = widget.topic == null ? all : [for (final n in all) if (n.topic == widget.topic) n];
    final sections = _sections(notes);
    final title = widget.topic ?? categoryDisplayName(context, widget.category);
    final learned = notes.where((n) => leafLook(n) == LeafLook.green).length;
    final latest = notes.isEmpty
        ? null
        : notes.map((n) => n.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final local = MaterialLocalizations.of(context);
    final numbered = sections.length > 1 || sections.any((s) => s.$1 != null);

    return Scaffold(
      backgroundColor: paper.desk,
      appBar: AppBar(
        backgroundColor: paper.desk,
        foregroundColor: paper.ink,
        title: Text(title, style: TextStyle(fontFamily: paperFont, color: paper.ink)),
        actions: [
          IconButton(
            tooltip: strings.practiseAll,
            icon: const Icon(Icons.play_circle_outline),
            onPressed: notes.isEmpty
                ? null
                : () => startSession(context, studyOrder(notes),
                    scope: PracticeScope.category,
                    category: widget.category,
                    topic: widget.topic),
          ),
          IconButton(
            tooltip: strings.exportMarkdown,
            icon: const Icon(Icons.ios_share),
            onPressed: notes.isEmpty ? null : () => _export(title, sections),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: paper.page,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: paper.dark ? 0.4 : 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: CustomPaint(
                isComplex: true,
                willChange: false,
                painter: _DotGrid(paper.dots),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TitlePage(
                        paper: paper,
                        overline: widget.topic == null
                            ? strings.paperOverline
                            : categoryDisplayName(context, widget.category).toUpperCase(),
                        title: title,
                        meta: [
                          strings.notesCount(notes.length),
                          strings.learnedOf(learned, notes.length),
                          if (latest != null) local.formatMediumDate(latest),
                        ].join('  ·  '),
                        progress: notes.isEmpty ? 0 : learned / notes.length,
                      ),
                      if (numbered && sections.length > 1) ...[
                        const SizedBox(height: 28),
                        _Contents(
                          paper: paper,
                          entries: [
                            for (final (topic, list) in sections)
                              (topic ?? strings.otherNotes, list.length),
                          ],
                          onTap: (i) {
                            final key = _sectionKeys['$i'];
                            final ctx = key?.currentContext;
                            if (ctx != null) {
                              Scrollable.ensureVisible(ctx,
                                  duration: const Duration(milliseconds: 450),
                                  curve: Curves.easeOutCubic);
                            }
                          },
                        ),
                      ],
                      if (notes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(strings.paperEmpty,
                              style: TextStyle(color: paper.faded, fontFamily: paperFont)),
                        ),
                      for (final (i, (topic, list)) in sections.indexed) ...[
                        const SizedBox(height: 36),
                        if (numbered)
                          _SectionHeading(
                            key: _sectionKeys.putIfAbsent('$i', GlobalKey.new),
                            paper: paper,
                            number: i + 1,
                            title: topic ?? strings.otherNotes,
                          ),
                        for (final n in list)
                          _Entry(
                            note: n,
                            paper: paper,
                            onTap: () => showNoteDetailSheet(context, n),
                          ),
                      ],
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 36),
                        Center(
                          child: Icon(Icons.eco_outlined, size: 26, color: paper.accent),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitlePage extends StatelessWidget {
  const _TitlePage({
    required this.paper,
    required this.overline,
    required this.title,
    required this.meta,
    required this.progress,
  });

  final _Paper paper;
  final String overline;
  final String title;
  final String meta;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(overline,
            style: TextStyle(
                fontFamily: appFont,
                fontSize: 12,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
                color: paper.accent)),
        const SizedBox(height: 10),
        Text(title,
            style: TextStyle(
                fontFamily: paperFont,
                fontSize: 40,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: paper.ink,
                letterSpacing: -0.5)),
        const SizedBox(height: 14),
        Text(meta, style: TextStyle(fontFamily: appFont, fontSize: 13, color: paper.faded)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: summerLeafColor,
              backgroundColor: paper.faded.withValues(alpha: 0.18),
            ),
          ),
        ),
      ],
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({required this.paper, required this.entries, required this.onTap});

  final _Paper paper;
  final List<(String, int)> entries;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: BoxDecoration(
        border: Border.all(color: paper.faded.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.s.contents.toUpperCase(),
              style: TextStyle(
                  fontFamily: appFont,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: paper.faded)),
          const SizedBox(height: 6),
          for (final (i, (name, count)) in entries.indexed)
            InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text((i + 1).toString().padLeft(2, '0'),
                          style: TextStyle(
                              fontFamily: paperFont,
                              fontWeight: FontWeight.w700,
                              color: paper.accent)),
                    ),
                    Expanded(
                      child: Text(name,
                          style: TextStyle(fontFamily: paperFont, fontSize: 17, color: paper.ink)),
                    ),
                    Text('$count',
                        style: TextStyle(fontFamily: appFont, fontSize: 12, color: paper.faded)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
      {super.key, required this.paper, required this.number, required this.title});

  final _Paper paper;
  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(number.toString().padLeft(2, '0'),
                  style: TextStyle(
                      fontFamily: paperFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: paper.accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontFamily: paperFont,
                        fontSize: 27,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: paper.ink)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // A brush-like underline that fades out.
          Container(
            height: 3,
            width: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                  colors: [paper.accent, paper.accent.withValues(alpha: 0)]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One note on the page: its kind's colour down the margin, the cue as a
/// serif heading, the answer formatted, highlights marked.
class _Entry extends StatelessWidget {
  const _Entry({required this.note, required this.paper, required this.onTap});

  final KnowledgeItem note;
  final _Paper paper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final back = note.back?.trim();
    final body = back == null || back.isEmpty
        ? null
        : note.type == KnowledgeType.code && !back.startsWith('```')
            ? '```\n$back\n```'
            : back;
    final look = leafLook(note);
    final dot = note.lastReviewedAt == null
        ? paper.faded.withValues(alpha: 0.5)
        : switch (look) {
            LeafLook.green => summerLeafColor,
            LeafLook.gold => autumnLeafColor,
            _ => const Color(0xFF9A6B3F),
          };
    final question = note.type == KnowledgeType.question;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 14),
              child: TypeChip(type: note.type, size: 28),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: NoteText(
                          text: note.front,
                          highlights: note.highlights,
                          style: TextStyle(
                            fontFamily: paperFont,
                            fontSize: 20,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            fontStyle: question ? FontStyle.italic : FontStyle.normal,
                            color: paper.ink,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 9, left: 8),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                      ),
                    ],
                  ),
                  if (body != null) ...[
                    const SizedBox(height: 6),
                    Theme(
                      // Formatted parts (lists, quotes) take the paper's ink.
                      data: theme.copyWith(
                        colorScheme: theme.colorScheme.copyWith(
                          primary: paper.accent,
                          onSurface: paper.ink,
                          onSurfaceVariant: paper.faded,
                        ),
                      ),
                      child: NoteText(
                        text: body,
                        highlights: note.highlights,
                        style: TextStyle(
                            fontFamily: appFont, fontSize: 15.5, height: 1.6, color: paper.ink),
                      ),
                    ),
                  ],
                  if (note.hasImage) ...[
                    const SizedBox(height: 10),
                    NoteImage(noteId: note.id, maxHeight: 180),
                  ],
                  if (note.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(note.tags.map((t) => '#$t').join('  '),
                        style: TextStyle(fontFamily: appFont, fontSize: 12, color: paper.faded)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A faint dot grid, like a bullet-journal page.
class _DotGrid extends CustomPainter {
  _DotGrid(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 22.0;
    final paint = Paint()..color = color;
    for (var y = step; y < size.height; y += step) {
      for (var x = step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid old) => old.color != color;
}
