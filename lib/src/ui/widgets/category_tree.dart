import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../providers/knowledge_providers.dart';
import 'share_category.dart';
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

/// How a note's leaf looks.
enum LeafLook {
  /// Learned and not due: summer green.
  green,

  /// Needs training (new, missed, or due): autumn gold.
  gold,

  /// Overdue for days: brown, drooping.
  wilting,

  /// Overdue for weeks: lying on the ground under the tree.
  fallen,
}

/// Days overdue after which a leaf wilts, and after which it falls.
const int wiltAfterDays = 4;
const int fallAfterDays = 14;

LeafLook leafLook(KnowledgeItem item, {DateTime? now}) {
  final at = now ?? DateTime.now();
  if (item.lastReviewedAt != null && item.isDue(at)) {
    final overdue = at.difference(item.dueDate).inDays;
    if (overdue >= fallAfterDays) return LeafLook.fallen;
    if (overdue >= wiltAfterDays) return LeafLook.wilting;
  }
  return leafNeedsTraining(item, now: at) ? LeafLook.gold : LeafLook.green;
}

/// What a well-kept tree grows.
enum TreeBloom { none, blossom, fruit }

/// Blossoms once every note (at least 3) is green; fruit once they are also
/// settled in memory (each next review three weeks or more away).
TreeBloom treeBloom(List<KnowledgeItem> notes, {DateTime? now}) {
  if (notes.length < 3) return TreeBloom.none;
  if (notes.any((n) => leafLook(n, now: now) != LeafLook.green)) return TreeBloom.none;
  return notes.every((n) => n.intervalDays >= 21) ? TreeBloom.fruit : TreeBloom.blossom;
}

/// Per note, whether its leaf lies on the ground (for tapping it there).
List<bool> fallenLeaves(List<KnowledgeItem> notes, {DateTime? now}) =>
    [for (final n in notes) leafLook(n, now: now) == LeafLook.fallen];

/// The synthetic ungrouped bucket is shown in the interface language.
String categoryDisplayName(BuildContext context, String category) =>
    _displayName(context, category);

String _displayName(BuildContext context, String category) =>
    category == kUngroupedCategory ? context.s.ungrouped : category;

/// Notes in leaf order: oldest first, so existing leaves keep their spot as new
/// notes sprout.
List<KnowledgeItem> leafOrder(List<KnowledgeItem> notes) =>
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
    final ordered = leafOrder(notes);
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
                  tooltip: context.s.shareCategory,
                  icon: const Icon(Icons.ios_share, size: 20),
                  onPressed: () => showShareCategory(context, category, notes),
                ),
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
                    final hit = model.leafAt(p,
                        slop: 14 / scale - 14, fallen: fallenLeaves(ordered));
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
                          slop: math.max(0, 14 / scale - 14),
                          fallen: fallenLeaves(widget.notes));
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

/// Paints a [TreeModel] at its natural size with one leaf per note, and
/// keeps it alive: leaves sway, a leaf turns from gold to green when its note
/// is learned, long-overdue leaves wilt and fall, and a fully learned tree
/// blossoms, then bears fruit. Motion stops when the system asks for reduced
/// motion.
class TreeCanvas extends StatefulWidget {
  const TreeCanvas(
      {super.key, required this.model, required this.notes, this.still = false});

  final TreeModel model;
  final List<KnowledgeItem> notes;

  /// Drawn without motion (e.g. into an image for the home-screen widget).
  final bool still;

  @override
  State<TreeCanvas> createState() => _TreeCanvasState();
}

class _TreeCanvasState extends State<TreeCanvas> with TickerProviderStateMixin {
  late final AnimationController _sway =
      AnimationController(vsync: this, duration: const Duration(seconds: 7));
  late final AnimationController _greening =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  /// Notes whose leaf is turning green right now.
  Set<String> _turning = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        widget.still || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _sway.stop();
    } else if (!_sway.isAnimating) {
      _sway.repeat();
    }
  }

  @override
  void didUpdateWidget(TreeCanvas old) {
    super.didUpdateWidget(old);
    final before = {for (final n in old.notes) n.id: leafLook(n)};
    final turned = {
      for (final n in widget.notes)
        if (before[n.id] != null &&
            before[n.id] != LeafLook.green &&
            leafLook(n) == LeafLook.green)
          n.id,
    };
    if (turned.isNotEmpty) {
      _turning = turned;
      _greening.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    _greening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final looks = [for (final n in widget.notes) leafLook(n, now: now)];
    final bloom = treeBloom(widget.notes, now: now);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_sway, _greening]),
        builder: (context, _) {
          final greening = _greening.isAnimating ? _greening.value : 1.0;
          return CustomPaint(
            size: widget.model.size,
            painter: _TreePainter(
              model: widget.model,
              looks: looks,
              turning: [
                for (final n in widget.notes)
                  _turning.contains(n.id) && greening < 1 ? greening : null,
              ],
              sway: _sway.value,
              bloom: bloom,
              dark: dark,
            ),
          );
        },
      ),
    );
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.model,
    required this.looks,
    required this.turning,
    required this.sway,
    required this.bloom,
    required this.dark,
  });

  final TreeModel model;
  final List<LeafLook> looks;

  /// Per leaf: progress (0–1) of turning from gold to green, or null.
  final List<double?> turning;

  /// Position in the sway cycle, 0–1.
  final double sway;
  final TreeBloom bloom;
  final bool dark;

  // Leaf palettes: [light, dark, vein/edge].
  static const _summer = [Color(0xFF8BCF6A), Color(0xFF2F7D32), Color(0xFF1E5A22)];
  static const _summerAlt = [Color(0xFFA6D96A), Color(0xFF4A8F2A), Color(0xFF2E6118)];
  static const _autumn = [Color(0xFFFFE082), Color(0xFFE8A317), Color(0xFFA86A00)];
  static const _autumnAlt = [Color(0xFFFFCC66), Color(0xFFE07B12), Color(0xFF9A4E00)];
  static const _withered = [Color(0xFFD9B48C), Color(0xFF9C6B3F), Color(0xFF6E4524)];

  @override
  void paint(Canvas canvas, Size size) {
    _paintGround(canvas);
    _paintBranches(canvas);
    // Fallen leaves lie on the ground, under the canopy.
    for (var i = 0; i < model.leaves.length; i++) {
      if (_look(i) == LeafLook.fallen) {
        _paintLeaf(canvas, model.fallenSlot(i), _withered);
      }
    }
    for (var i = 0; i < model.leaves.length; i++) {
      final look = _look(i);
      if (look == LeafLook.fallen) continue;
      final slot = model.leaves[i];
      final alt = slot.tint > 0.35;
      // Each leaf sways on its own phase; wilting ones droop and barely move.
      final phase = slot.position.dx * 0.045 + slot.tint * 2;
      final swing = math.sin(2 * math.pi * sway + phase) *
          (look == LeafLook.wilting ? 0.025 : 0.075);
      var angle = slot.angle + swing;
      if (look == LeafLook.wilting) {
        angle += _towardsDown(angle) * 0.55;
      }
      final turn = i < turning.length ? turning[i] : null;
      final palette = switch (look) {
        LeafLook.wilting => _withered,
        LeafLook.gold => alt ? _autumnAlt : _autumn,
        _ when turn != null => [
            for (var k = 0; k < 3; k++)
              Color.lerp((alt ? _autumnAlt : _autumn)[k], (alt ? _summerAlt : _summer)[k],
                  Curves.easeInOut.transform(turn))!,
          ],
        _ => alt ? _summerAlt : _summer,
      };
      if (turn != null) _paintGlow(canvas, slot, turn);
      _paintLeaf(canvas, LeafSlot(slot.position, angle, slot.tint), palette);
    }
    if (bloom != TreeBloom.none) _paintBloom(canvas);
  }

  LeafLook _look(int i) => i < looks.length ? looks[i] : LeafLook.gold;

  /// Signed turn from [angle] towards pointing straight down.
  static double _towardsDown(double angle) {
    var d = (math.pi / 2 - angle) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d;
  }

  /// A soft light behind a leaf that just turned green.
  void _paintGlow(Canvas canvas, LeafSlot slot, double t) {
    final center = slot.position +
        Offset(math.cos(slot.angle), math.sin(slot.angle)) * (TreeModel.leafLength * 0.5);
    final strength = math.sin(t * math.pi);
    canvas.drawCircle(
      center,
      TreeModel.leafLength * (0.8 + t * 0.6),
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFFFF59D).withValues(alpha: 0.75 * strength),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: center, radius: TreeModel.leafLength * 1.4)),
    );
  }

  /// Flowers (or fruit) at the tips of every other twig.
  void _paintBloom(Canvas canvas) {
    // Twigs are the thinnest limbs (how thin depends on the tree's size).
    final thinnest = model.branches.map((b) => b.endWidth).reduce(math.min);
    final twigs = [
      for (final b in model.branches)
        if (b.endWidth <= thinnest * 1.25) b,
    ];
    for (var i = 0; i < twigs.length; i += 2) {
      final at = twigs[i].end;
      if (bloom == TreeBloom.fruit) {
        const r = 4.6;
        canvas.drawLine(at, at + const Offset(0, 3),
            Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1);
        final center = at + const Offset(0, 3 + r);
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(-0.4, -0.4),
              colors: [Color(0xFFFF8A80), Color(0xFFC62828)],
            ).createShader(Rect.fromCircle(center: center, radius: r)),
        );
      } else {
        const petal = 2.6;
        final petals = Paint()..color = const Color(0xFFF8BBD0);
        for (var k = 0; k < 5; k++) {
          final a = k * 2 * math.pi / 5 + i;
          canvas.drawCircle(at + Offset(math.cos(a), math.sin(a)) * petal, petal, petals);
        }
        canvas.drawCircle(at, 1.6, Paint()..color = const Color(0xFFFFD54F));
      }
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

  void _paintLeaf(Canvas canvas, LeafSlot leaf, List<Color> palette) {
    const len = TreeModel.leafLength;
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
  bool shouldRepaint(covariant _TreePainter old) => true;
}
