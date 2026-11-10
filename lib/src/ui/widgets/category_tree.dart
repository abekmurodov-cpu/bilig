import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../providers/knowledge_providers.dart';
import 'tree_model.dart';

/// Whether a note's leaf is "autumn" (needs training): never reviewed, last
/// recall wrong, or due again. Recalled notes that aren't due stay green.
bool leafNeedsTraining(KnowledgeItem item, {DateTime? now}) =>
    item.lastCorrect != true || item.isDue(now ?? DateTime.now());

/// Base color a leaf takes: summer green when learned, autumn gold otherwise.
Color leafColor(KnowledgeItem item, {DateTime? now}) =>
    leafNeedsTraining(item, now: now) ? autumnLeafColor : summerLeafColor;

const Color summerLeafColor = Color(0xFF3E9B3A);
const Color autumnLeafColor = Color(0xFFE8A317);

/// The synthetic ungrouped bucket is shown in the interface language.
String _displayName(BuildContext context, String category) =>
    category == kUngroupedCategory ? context.s.ungrouped : category;

/// Notes in leaf order: oldest first, so existing leaves keep their spot as new
/// notes sprout.
List<KnowledgeItem> _leafOrder(List<KnowledgeItem> notes) =>
    List.of(notes)..sort((a, b) => a.createdAt.compareTo(b.createdAt));

/// A category drawn as a living tree whose size and shape grow with its note
/// count (see [TreeModel]). Small trees render at natural size, so a category
/// with few notes really is a small sapling; large trees are scaled to fit the
/// card. Tapping a leaf opens its note; tapping elsewhere (or the zoom button)
/// opens [TreeViewerScreen] to pan and zoom.
class CategoryTree extends StatelessWidget {
  const CategoryTree({
    super.key,
    required this.category,
    required this.notes,
    required this.onLeafTap,
    this.maxHeight = 320,
  });

  final String category;
  final List<KnowledgeItem> notes;
  final void Function(KnowledgeItem) onLeafTap;
  final double maxHeight;

  void _openViewer(BuildContext context, List<KnowledgeItem> ordered,
      TreeModel model) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TreeViewerScreen(
        category: category,
        notes: ordered,
        model: model,
        onLeafTap: onLeafTap,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = _leafOrder(notes);
    final model = TreeModel.generate(count: ordered.length, seed: category);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Icon(Icons.park_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _displayName(context, category),
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${notes.length}', style: theme.textTheme.labelMedium),
                IconButton(
                  tooltip: context.s.zoom,
                  icon: const Icon(Icons.zoom_out_map, size: 20),
                  onPressed: () => _openViewer(context, ordered, model),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final scale = math.min(
                1.0,
                math.min(width / model.size.width,
                    maxHeight / model.size.height),
              );
              final height = model.size.height * scale;
              return SizedBox(
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    // Card coords → tree coords (tree is centered).
                    final dx = (width - model.size.width * scale) / 2;
                    final p = (d.localPosition - Offset(dx, 0)) / scale;
                    // At small scales, widen the target to a ~14px finger.
                    final hit = model.leafAt(p, slop: 14 / scale - 14);
                    if (hit != null) {
                      onLeafTap(ordered[hit]);
                    } else {
                      _openViewer(context, ordered, model);
                    }
                  },
                  child: Center(
                    child: SizedBox(
                      width: model.size.width * scale,
                      height: height,
                      child: FittedBox(
                        child: TreeCanvas(model: model, notes: ordered),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Full-screen pan + zoom view of one tree (pinch, mouse wheel, trackpad, or
/// the zoom buttons). Starts fitted to the screen.
class TreeViewerScreen extends StatefulWidget {
  const TreeViewerScreen({
    super.key,
    required this.category,
    required this.notes,
    required this.model,
    required this.onLeafTap,
  });

  final String category;
  final List<KnowledgeItem> notes;
  final TreeModel model;
  final void Function(KnowledgeItem) onLeafTap;

  @override
  State<TreeViewerScreen> createState() => _TreeViewerScreenState();
}

class _TreeViewerScreenState extends State<TreeViewerScreen> {
  final _controller = TransformationController();
  Size _viewport = Size.zero;
  double _fitScale = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit() {
    final size = widget.model.size;
    _fitScale = math.min(
      1.5,
      math.min(_viewport.width / size.width, _viewport.height / size.height),
    );
    final dx = (_viewport.width - size.width * _fitScale) / 2;
    final dy = (_viewport.height - size.height * _fitScale) / 2;
    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(_fitScale, _fitScale, 1, 1);
  }

  /// Zooms by [factor] around the viewport center.
  void _zoom(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    final f = target / current;
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    _controller.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_controller.value);
  }

  double get _minScale => math.min(_fitScale, 1) * 0.5;
  static const double _maxScale = 6;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName(context, widget.category)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${widget.notes.length}'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          if (viewport != _viewport) {
            _viewport = viewport;
            _fit();
          }
          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  boundaryMargin: EdgeInsets.symmetric(
                    horizontal: viewport.width * 0.6,
                    vertical: viewport.height * 0.6,
                  ),
                  child: GestureDetector(
                    onTapUp: (d) {
                      final scale = _controller.value.getMaxScaleOnAxis();
                      final hit = model.leafAt(d.localPosition,
                          slop: math.max(0, 14 / scale - 14));
                      if (hit != null) widget.onLeafTap(widget.notes[hit]);
                    },
                    child: TreeCanvas(model: model, notes: widget.notes),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  children: [
                    _ZoomButton(
                      icon: Icons.add,
                      tooltip: context.s.zoomIn,
                      onPressed: () => _zoom(1.4),
                    ),
                    const SizedBox(height: 8),
                    _ZoomButton(
                      icon: Icons.remove,
                      tooltip: context.s.zoomOut,
                      onPressed: () => _zoom(1 / 1.4),
                    ),
                    const SizedBox(height: 8),
                    _ZoomButton(
                      icon: Icons.fit_screen,
                      tooltip: context.s.fit,
                      onPressed: () => setState(_fit),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// Paints a [TreeModel] at its natural size with one leaf per note.
class TreeCanvas extends StatelessWidget {
  const TreeCanvas({super.key, required this.model, required this.notes});

  final TreeModel model;
  final List<KnowledgeItem> notes;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    return RepaintBoundary(
      child: CustomPaint(
        size: model.size,
        painter: _TreePainter(
          model: model,
          autumn: [for (final n in notes) leafNeedsTraining(n, now: now)],
          dark: dark,
        ),
      ),
    );
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter({required this.model, required this.autumn, required this.dark});

  final TreeModel model;

  /// Per leaf: true = autumn gold (needs training), false = green.
  final List<bool> autumn;
  final bool dark;

  // Leaf palettes: [light, dark, vein/edge].
  static const _summer = [Color(0xFF8BCF6A), Color(0xFF2F7D32), Color(0xFF1E5A22)];
  static const _summerAlt = [Color(0xFFA6D96A), Color(0xFF4A8F2A), Color(0xFF2E6118)];
  static const _autumn = [Color(0xFFFFE082), Color(0xFFE8A317), Color(0xFFA86A00)];
  static const _autumnAlt = [Color(0xFFFFCC66), Color(0xFFE07B12), Color(0xFF9A4E00)];

  @override
  void paint(Canvas canvas, Size size) {
    _paintGround(canvas);
    _paintBranches(canvas);
    for (var i = 0; i < model.leaves.length; i++) {
      _paintLeaf(canvas, model.leaves[i], i < autumn.length && autumn[i]);
    }
  }

  void _paintGround(Canvas canvas) {
    final base = model.branches.first.start;
    final w = model.trunkWidth * 3 + 22;
    final rect = Rect.fromCenter(
        center: base + const Offset(0, 2), width: w * 2, height: 10 + w * 0.12);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [
          (dark ? const Color(0xFF6B8F4E) : const Color(0xFF7FA65A))
              .withValues(alpha: 0.55),
          Colors.transparent,
        ]).createShader(rect),
    );
  }

  void _paintBranches(Canvas canvas) {
    final bark = dark ? const Color(0xFF9C7A62) : const Color(0xFF6B4A35);
    final barkShade = dark ? const Color(0xFF7A5C48) : const Color(0xFF4E3424);
    final fill = Paint()..color = bark;
    final shade = Paint()..color = barkShade.withValues(alpha: 0.3);

    // Root flare first, so the trunk's shading runs over it.
    final trunk = model.branches.first;
    final w = trunk.startWidth;
    final root = Path()
      ..moveTo(trunk.start.dx - w * 1.1, trunk.start.dy)
      ..quadraticBezierTo(trunk.start.dx - w * 0.45, trunk.start.dy - w * 0.25,
          trunk.start.dx - w * 0.3, trunk.start.dy - w * 0.9)
      ..lineTo(trunk.start.dx + w * 0.3, trunk.start.dy - w * 0.9)
      ..quadraticBezierTo(trunk.start.dx + w * 0.45, trunk.start.dy - w * 0.25,
          trunk.start.dx + w * 1.1, trunk.start.dy)
      ..close();
    canvas.drawPath(root, fill);
    for (final b in model.branches) {
      final path = _taperedPath(b);
      canvas.drawPath(path, fill);
      // Rounded joint so limbs blend into their parent.
      canvas.drawCircle(b.end, b.endWidth / 2, fill);
    }
    // A shaded side on thick limbs reads as volume.
    for (final b in model.branches) {
      if (b.startWidth < 5) continue;
      final dir = b.end - b.start;
      final n = Offset(-dir.dy, dir.dx) / dir.distance;
      final shifted = TreeBranch(
        start: b.start + n * (b.startWidth * 0.18),
        end: b.end + n * (b.endWidth * 0.18),
        control: b.control + n * ((b.startWidth + b.endWidth) * 0.09),
        startWidth: b.startWidth * 0.45,
        endWidth: b.endWidth * 0.45,
      );
      canvas.drawPath(_taperedPath(shifted), shade);
    }
  }

  /// Outline of a quadratic bezier limb whose width tapers start → end.
  Path _taperedPath(TreeBranch b) {
    const steps = 8;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final mt = 1 - t;
      final p = b.start * (mt * mt) + b.control * (2 * mt * t) + b.end * (t * t);
      final d = (b.control - b.start) * (2 * mt) + (b.end - b.control) * (2 * t);
      final len = d.distance == 0 ? 1.0 : d.distance;
      final n = Offset(-d.dy / len, d.dx / len);
      final w = (b.startWidth + (b.endWidth - b.startWidth) * t) / 2;
      left.add(p + n * w);
      right.add(p - n * w);
    }
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  void _paintLeaf(Canvas canvas, LeafSlot leaf, bool isAutumn) {
    const len = TreeModel.leafLength;
    // Alternate shade for some leaves so the crown has depth.
    final alt = leaf.tint > 0.35;
    final palette = isAutumn
        ? (alt ? _autumnAlt : _autumn)
        : (alt ? _summerAlt : _summer);
    final scale = 0.85 + (leaf.tint.abs() * 0.3);

    canvas.save();
    canvas.translate(leaf.position.dx, leaf.position.dy);
    canvas.rotate(leaf.angle);
    canvas.scale(scale);

    // Short stem, then an almond-shaped blade.
    const stem = 3.0;
    canvas.drawLine(
      Offset.zero,
      const Offset(stem, 0),
      Paint()
        ..color = palette[2]
        ..strokeWidth = 1.1,
    );
    final blade = Path()
      ..moveTo(stem, 0)
      ..cubicTo(stem + len * 0.25, -len * 0.4, len * 0.8, -len * 0.3, len + 2, 0)
      ..cubicTo(len * 0.8, len * 0.3, stem + len * 0.25, len * 0.4, stem, 0)
      ..close();
    final bounds = Rect.fromLTRB(stem, -len * 0.4, len + 2, len * 0.4);
    canvas.drawPath(
      blade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette[0], palette[1]],
        ).createShader(bounds),
    );
    // Midrib and a pair of side veins.
    final vein = Paint()
      ..color = palette[2].withValues(alpha: 0.55)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(stem, 0), const Offset(len, 0), vein);
    for (final x in const [0.4, 0.62]) {
      canvas.drawLine(Offset(len * x, 0), Offset(len * (x + 0.15), -len * 0.15), vein);
      canvas.drawLine(Offset(len * x, 0), Offset(len * (x + 0.15), len * 0.15), vein);
    }
    canvas.drawPath(
      blade,
      Paint()
        ..color = palette[2].withValues(alpha: 0.6)
        ..strokeWidth = 0.6
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TreePainter old) =>
      old.model != model || old.dark != dark || !_sameList(old.autumn, autumn);

  static bool _sameList(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
