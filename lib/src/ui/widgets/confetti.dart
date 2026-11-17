import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A short burst of confetti over the screen, for a reached goal or a great
/// session. Skipped when the system asks for reduced motion.
void showConfetti(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(child: _Confetti(onDone: () => entry.remove())),
  );
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward().whenComplete(widget.onDone);
  final _rng = math.Random();
  late final List<_Piece> _pieces = List.generate(
    90,
    (_) => _Piece(
      x: _rng.nextDouble(),
      speed: 0.7 + _rng.nextDouble() * 0.6,
      drift: (_rng.nextDouble() - 0.5) * 0.25,
      spin: (_rng.nextDouble() - 0.5) * 12,
      size: 5 + _rng.nextDouble() * 6,
      delay: _rng.nextDouble() * 0.25,
      color: const [
        Color(0xFF5B6CF0),
        Color(0xFFF08C2E),
        Color(0xFF3E9B3A),
        Color(0xFFE8A317),
        Color(0xFFE0603A),
        Color(0xFF8E5BD8),
      ][_rng.nextInt(6)],
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: MediaQuery.sizeOf(context),
          painter: _ConfettiPainter(_pieces, _c.value),
        ),
      );
}

class _Piece {
  const _Piece({
    required this.x,
    required this.speed,
    required this.drift,
    required this.spin,
    required this.size,
    required this.delay,
    required this.color,
  });

  final double x, speed, drift, spin, size, delay;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = (p.x + p.drift * local) * size.width;
      final paint = Paint()..color = p.color.withValues(alpha: (1 - local * local).clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
