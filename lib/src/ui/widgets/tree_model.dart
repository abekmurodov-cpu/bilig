import 'dart:math' as math;
import 'dart:ui';

/// One limb of a tree: a tapered, slightly curved segment from [start] to [end].
class TreeBranch {
  const TreeBranch({
    required this.start,
    required this.end,
    required this.control,
    required this.startWidth,
    required this.endWidth,
  });

  final Offset start;
  final Offset end;

  /// Quadratic-bezier control point that gives the limb its gentle bend.
  final Offset control;
  final double startWidth;
  final double endWidth;
}

/// Where a leaf hangs: its stem point and the direction it points (radians).
class LeafSlot {
  const LeafSlot(this.position, this.angle, this.tint);

  final Offset position;
  final double angle;

  /// Per-leaf variation in [-1, 1] so a canopy isn't one flat color.
  final double tint;
}

/// Procedurally generated tree geometry for a category with [count] notes.
///
/// Trees grow in pre-designed **stages**: each stage has a fixed leaf capacity
/// (2, 5, 12, 25, 50, 100, then doubling), and a deeper, taller, thicker
/// skeleton than the last. Within a stage the skeleton is identical, so adding
/// a note only fills the next free leaf slot; crossing a threshold grows the
/// whole tree. Geometry is seeded by the category name, so every category keeps
/// its own recognizable shape.
///
/// Coordinates are in logical pixels with the origin at the top-left of
/// [size]; leaves are [leafLength] long regardless of stage, so a big tree is
/// physically larger rather than a scaled-up small one.
class TreeModel {
  TreeModel._(this.stage, this.branches, this.leaves, this.size, this.groundY);

  static const double leafLength = 18;
  static const double _margin = 24;

  final int stage;
  final List<TreeBranch> branches;

  /// Exactly one slot per note, in note order.
  final List<LeafSlot> leaves;
  final Size size;
  final double groundY;

  /// Root-collar width, used to size the ground mound.
  double get trunkWidth => branches.isEmpty ? 0 : branches.first.startWidth;

  static int stageFor(int count) {
    var stage = 0;
    while (capacityOf(stage) < count) {
      stage++;
    }
    return stage;
  }

  static int capacityOf(int stage) {
    const fixed = [2, 5, 12, 25, 50, 100];
    if (stage < fixed.length) return fixed[stage];
    return 100 * (1 << (stage - fixed.length + 1));
  }

  factory TreeModel.generate({required int count, required String seed}) {
    final stage = stageFor(math.max(count, 1));
    final capacity = capacityOf(stage);
    // Deepen until there are enough twigs to hold the stage's capacity.
    var depth = 2;
    late _Growth growth;
    while (true) {
      growth = _Growth(stage: stage, depth: depth, seed: _hash(seed) ^ stage);
      if (growth.slotsByTwig.length * _Growth.slotsPerTwig >= capacity ||
          depth > 12) {
        break;
      }
      depth++;
    }

    final ordered = growth.orderedSlots();
    final leaves = ordered.take(count).toList();

    // Fit everything into a positive-coordinate box.
    var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
    void include(Offset p, double pad) {
      minX = math.min(minX, p.dx - pad);
      maxX = math.max(maxX, p.dx + pad);
      minY = math.min(minY, p.dy - pad);
      maxY = math.max(maxY, p.dy + pad);
    }

    for (final b in growth.branches) {
      include(b.start, b.startWidth);
      include(b.end, b.endWidth);
    }
    // Reserve room for the full canopy so the box doesn't change as leaves fill.
    for (final s in ordered) {
      include(s.position, leafLength);
    }
    final trunkWidth = growth.branches.first.startWidth;
    include(Offset(-trunkWidth * 3, 0), 12);
    include(Offset(trunkWidth * 3, 0), 12);

    final shift = Offset(_margin - minX, _margin - minY);
    TreeBranch move(TreeBranch b) => TreeBranch(
          start: b.start + shift,
          end: b.end + shift,
          control: b.control + shift,
          startWidth: b.startWidth,
          endWidth: b.endWidth,
        );
    return TreeModel._(
      stage,
      [for (final b in growth.branches) move(b)],
      [for (final l in leaves) LeafSlot(l.position + shift, l.angle, l.tint)],
      Size(maxX - minX + _margin * 2, maxY - minY + _margin * 2 + 8),
      shift.dy,
    );
  }

  /// Where leaf [i] lies once it has fallen: scattered on the ground under
  /// the tree, the same spot every time.
  LeafSlot fallenSlot(int i) {
    final base = branches.first.start;
    final rng = math.Random(i * 7919 + 17);
    final reach = trunkWidth * 2.5 + 26;
    return LeafSlot(
      base + Offset((rng.nextDouble() * 2 - 1) * reach, 1 + rng.nextDouble() * 4),
      (rng.nextBool() ? 0.0 : math.pi) + (rng.nextDouble() - 0.5) * 0.6,
      leaves[i].tint,
    );
  }

  /// Index of the leaf under [point] (tree coordinates), or null. Leaves
  /// marked in [fallen] are looked for on the ground.
  int? leafAt(Offset point, {double slop = 0, List<bool> fallen = const []}) {
    int? best;
    var bestDist = leafLength * 0.75 + slop;
    for (var i = 0; i < leaves.length; i++) {
      final l = i < fallen.length && fallen[i] ? fallenSlot(i) : leaves[i];
      // Test against the leaf blade's center, not its stem.
      final center = l.position +
          Offset(math.cos(l.angle), math.sin(l.angle)) * (leafLength * 0.5);
      final d = (center - point).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// FNV-1a: a hash that is stable across runs and platforms.
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}

/// Recursive branching with a seeded RNG. The trunk starts at the origin and
/// grows up (negative y).
class _Growth {
  _Growth({required this.stage, required this.depth, required int seed})
      : _rng = math.Random(seed) {
    final trunkLength = 34 + 26 * math.pow(1.3, stage).toDouble();
    final trunkWidth = 4 + 3.2 * math.pow(1.42, stage).toDouble();
    _grow(
      start: Offset.zero,
      angle: -math.pi / 2 + _jitter(0.06),
      length: trunkLength,
      width: trunkWidth,
      level: 0,
    );
  }

  static const int slotsPerTwig = 5;

  final int stage;
  final int depth;
  final math.Random _rng;
  final List<TreeBranch> branches = [];

  /// Leaf slots grouped by the twig they grow on.
  final List<List<LeafSlot>> slotsByTwig = [];

  double _jitter(double amount) => (_rng.nextDouble() * 2 - 1) * amount;

  void _grow({
    required Offset start,
    required double angle,
    required double length,
    required double width,
    required int level,
  }) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final end = start + dir * length;
    final normal = Offset(-dir.dy, dir.dx);
    final bend = _jitter(length * 0.08);
    final control = start + dir * (length * 0.5) + normal * bend;
    final isTwig = level >= depth - 1;
    final endWidth = isTwig ? math.max(0.8, width * 0.35) : width * 0.68;
    branches.add(TreeBranch(
      start: start,
      end: end,
      control: control,
      startWidth: width,
      endWidth: endWidth,
    ));

    if (isTwig) {
      slotsByTwig.add(_twigLeaves(start, end, angle));
      return;
    }

    // 2 limbs, sometimes 3; the trunk of a large tree splits wider.
    final children = _rng.nextDouble() < (level == 0 ? 0.55 : 0.3) ? 3 : 2;
    final spread = level == 0 ? 0.62 : 0.5 + _jitter(0.08);
    for (var i = 0; i < children; i++) {
      final offset = (i - (children - 1) / 2) * spread;
      var childAngle = angle + offset + _jitter(0.14);
      // Gravitropism: limbs bend back toward the sky, more so near the top.
      childAngle += (-math.pi / 2 - childAngle) * 0.12;
      final childLength = length * (0.72 + _jitter(0.07));
      // Children sprout a little below the tip so joints overlap naturally.
      final from = level == 0 ? end : start + dir * (length * 0.96);
      _grow(
        start: from,
        angle: childAngle,
        length: childLength,
        width: endWidth,
        level: level + 1,
      );
    }
  }

  List<LeafSlot> _twigLeaves(Offset start, Offset end, double angle) {
    final dir = end - start;
    final side = _rng.nextBool() ? 1.0 : -1.0;
    LeafSlot slot(double t, double turn) => LeafSlot(
          start + dir * t,
          angle + turn + _jitter(0.2),
          _jitter(1),
        );
    return [
      slot(1.0, _jitter(0.15)), // tip
      slot(0.7, side * 0.85),
      slot(0.45, -side * 0.9),
      slot(0.85, -side * 0.75),
      slot(0.25, side * 1.0),
    ];
  }

  /// Slots in fill order: one leaf per twig (twigs shuffled) before any twig
  /// gets its second, so a sparse tree still covers its whole crown.
  List<LeafSlot> orderedSlots() {
    final twigOrder = List.generate(slotsByTwig.length, (i) => i)
      ..shuffle(_rng);
    return [
      for (var k = 0; k < slotsPerTwig; k++)
        for (final t in twigOrder) slotsByTwig[t][k],
    ];
  }
}
