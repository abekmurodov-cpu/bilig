import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../models/note_format.dart';
import 'category_tree.dart';

/// A note as a card: its kind, prompt and answer, and a line with where it
/// stands (new, due, or when it comes back) and its category. Shared between
/// Home and Notes; delete lives in the note's sheet.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.selected,
    this.selectedInPane = false,
    this.showCategory = true,
  });

  /// Open beside the list (wide screens).
  final bool selectedInPane;

  final KnowledgeItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// While choosing notes: whether this one is chosen (null otherwise).
  final bool? selected;

  /// Off where notes are already grouped by category.
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final (statusColor, status) = _status(context);
    final chosen = selected ?? false;
    return Card(
      color: chosen
          ? scheme.primaryContainer
          : selectedInPane
              ? scheme.secondaryContainer
              : null,
      shape: chosen
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.primary, width: 1.5))
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected != null)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(chosen ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: chosen ? scheme.primary : scheme.outline),
                )
              else
                TypeChip(type: item.type),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plainText(item.front),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                    const SizedBox(height: 3),
                    Text(
                      item.hasAnswer ? plainText(item.back!) : context.s.noAnswerYet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: item.hasAnswer
                          ? muted
                          : muted?.copyWith(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(status,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        if (showCategory && item.category != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.folder_outlined, size: 13, color: scheme.outline),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                                item.topic == null
                                    ? item.category!
                                    : '${item.category!} › ${item.topic!}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                        ],
                        if (item.highlights.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.border_color, size: 12, color: Colors.amber.shade700),
                          const SizedBox(width: 3),
                          Text('${item.highlights.length}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The leaf's color and a word on when the note comes back.
  (Color, String) _status(BuildContext context) {
    final now = DateTime.now();
    final strings = context.s;
    if (item.lastReviewedAt == null) {
      return (Theme.of(context).colorScheme.primary, strings.statusNew);
    }
    final color = switch (leafLook(item, now: now)) {
      LeafLook.green => summerLeafColor,
      LeafLook.gold => autumnLeafColor,
      LeafLook.wilting || LeafLook.fallen => const Color(0xFF9A6B3F),
    };
    if (item.isDue(now)) return (color, strings.statusDue);
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day);
    return (color, strings.nextIn(due.difference(today).inDays));
  }
}

/// The note's kind as an icon on a tinted rounded square, one hue per kind.
class TypeChip extends StatelessWidget {
  const TypeChip({super.key, required this.type, this.size = 40});

  final KnowledgeType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, hue) = switch (type) {
      KnowledgeType.fact => (Icons.lightbulb_outline, const Color(0xFFE0A100)),
      KnowledgeType.concept => (Icons.hub_outlined, const Color(0xFF5B6CF0)),
      KnowledgeType.command => (Icons.terminal, const Color(0xFF2E9E8F)),
      KnowledgeType.code => (Icons.code, const Color(0xFF8E5BD8)),
      KnowledgeType.question => (Icons.help_outline, const Color(0xFFE0603A)),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: context.s.noteType(type),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hue.withValues(alpha: dark ? 0.22 : 0.13),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon,
            size: size * 0.5,
            color: dark ? Color.lerp(hue, Colors.white, 0.35) : Color.lerp(hue, Colors.black, 0.15)),
      ),
    );
  }
}
