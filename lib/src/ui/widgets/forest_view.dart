import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../providers/knowledge_providers.dart';
import 'category_tree.dart';
import 'category_sheet.dart';
import 'tree_model.dart';

/// Every category as one garden: the trees side by side on a shared ground,
/// drawn to the same scale, so a student sees at a glance what they know
/// and what needs water. Tap a tree to walk around it.
class ForestView extends ConsumerWidget {
  const ForestView({super.key, this.height = 200});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(notesByCategoryProvider);
    if (groups.isEmpty) return const SizedBox.shrink();
    final trees = [
      for (final e in groups.entries)
        (
          category: e.key,
          notes: leafOrder(e.value),
          model: TreeModel.generate(count: e.value.length, seed: e.key),
        ),
    ];
    const labelHeight = 34.0;
    const ground = 16.0;
    final treeRoom = height - labelHeight - ground;
    // One scale for all, so a sapling stays small next to a big tree.
    final tallest = trees.map((t) => t.model.size.height).reduce(math.max);
    final scale = math.min(1.0, treeRoom / tallest);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF1B2735), Color(0xFF1E2B22)]
              : const [Color(0xFFE3F1FF), Color(0xFFF3F9EC)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: labelHeight - 2,
            height: ground,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? const [Color(0xFF3E5A32), Color(0xFF2C3F24)]
                      : const [Color(0xFFA5D27F), Color(0xFF7FB25B)],
                ),
              ),
            ),
          ),
          ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final t in trees)
                _ForestTree(
                  category: t.category,
                  notes: t.notes,
                  model: t.model,
                  scale: scale,
                  treeRoom: treeRoom,
                  ground: ground,
                  labelHeight: labelHeight,
                  labelStyle: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForestTree extends StatelessWidget {
  const _ForestTree({
    required this.category,
    required this.notes,
    required this.model,
    required this.scale,
    required this.treeRoom,
    required this.ground,
    required this.labelHeight,
    required this.labelStyle,
  });

  final String category;
  final List<KnowledgeItem> notes;
  final TreeModel model;
  final double scale;
  final double treeRoom;
  final double ground;
  final double labelHeight;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final learned = notes.where((n) => leafLook(n) == LeafLook.green).length;
    final width = math.max(model.size.width * scale, 64.0);
    // The tree's base sits on the ground line.
    final baseFromBottom = (model.size.height - model.groundY) * scale;
    return GestureDetector(
      onTap: () => showCategorySheet(context, category),
      child: SizedBox(
        width: width + 8,
        child: Column(
          children: [
            SizedBox(
              height: treeRoom + ground,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    bottom: ground * 0.55 - baseFromBottom,
                    child: SizedBox(
                      width: model.size.width * scale,
                      height: model.size.height * scale,
                      child: FittedBox(child: TreeCanvas(model: model, notes: notes)),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: labelHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(categoryDisplayName(context, category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle?.copyWith(fontWeight: FontWeight.w600)),
                  Text(context.s.learnedOf(learned, notes.length), style: labelStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
