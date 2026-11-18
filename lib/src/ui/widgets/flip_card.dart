import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:flutter/services.dart';

/// A Quizlet-style flashcard: a compact card that flips in 3D between [front]
/// and [back] on tap. Reports flips via [onFlip] so the parent can, e.g., reveal
/// grading buttons once the answer side has been shown.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.onFlip,
  });

  final Widget front;
  final Widget back;
  final ValueChanged<bool>? onFlip;

  @override
  State<FlipCard> createState() => FlipCardState();
}

class FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _showingBack = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Turns the card over (also used by the keyboard shortcut).
  void flip() {
    HapticFeedback.selectionClick();
    _showingBack = !_showingBack;
    if (_showingBack) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onFlip?.call(_showingBack);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: flip,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final angle = _controller.value * math.pi;
          final isBack = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015) // perspective
              ..rotateY(angle),
            child: isBack
                // Counter-rotate so the back face reads correctly.
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _Face(child: widget.back),
                  )
                : _Face(child: widget.front),
          );
        },
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 320,
      padding: const EdgeInsets.all(24),
      decoration: practiceCardDecoration(context),
      child: Center(
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

/// Which way a card was swiped.
enum SwipeDirection { left, right }

/// Lets the student swipe a card away: left for "Again", right for "Good".
/// The card follows the finger, tilts, and shows which grade it will give.
/// Swiping is off while [enabled] is false (before the answer is shown):
/// the card then only budges and springs back, and [onBlockedSwipe] tells
/// the parent so it can say why (tap to flip first).
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.child,
    required this.enabled,
    required this.onSwipe,
    required this.leftLabel,
    required this.rightLabel,
    this.onBlockedSwipe,
  });

  final Widget child;
  final bool enabled;
  final ValueChanged<SwipeDirection> onSwipe;
  final VoidCallback? onBlockedSwipe;
  final String leftLabel;
  final String rightLabel;

  @override
  State<SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _dx = 0;
  double _from = 0;

  /// How far (fraction of the width) a drag must go to count.
  static const double _threshold = 0.28;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  /// A swipe tried while swiping is off: spring back and report it.
  void _endBlocked() {
    if (_dx.abs() > 8) widget.onBlockedSwipe?.call();
    _from = _dx;
    _back.forward(from: 0);
  }

  void _end(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final far = _dx.abs() > width * _threshold;
    final fast = velocity.abs() > 900 && velocity.sign == _dx.sign;
    if (far || fast) {
      widget.onSwipe(_dx > 0 ? SwipeDirection.right : SwipeDirection.left);
      _dx = 0;
      setState(() {});
      return;
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final progress = widget.enabled
          ? (_dx / (width * _threshold)).clamp(-1.0, 1.0)
          : 0.0;
      final blocked = !widget.enabled && widget.onBlockedSwipe != null;
      final label = progress > 0 ? widget.rightLabel : widget.leftLabel;
      final color = progress > 0 ? const Color(0xFF2E9E4F) : const Color(0xFFD64545);
      return GestureDetector(
        onHorizontalDragUpdate: widget.enabled
            ? (d) => setState(() => _dx += d.delta.dx)
            : blocked
                // Stiff, so it feels held in place rather than broken.
                ? (d) => setState(() => _dx = (_dx + d.delta.dx * 0.2).clamp(-24.0, 24.0))
                : null,
        onHorizontalDragEnd: widget.enabled
            ? (d) => _end(d, width)
            : blocked
                ? (_) => _endBlocked()
                : null,
        child: Transform.translate(
          offset: Offset(_dx, 0),
          child: Transform.rotate(
            angle: progress * 0.12,
            child: Stack(
              children: [
                widget.child,
                if (progress.abs() > 0.05)
                  Positioned(
                    top: 18,
                    left: progress > 0 ? 18 : null,
                    right: progress < 0 ? 18 : null,
                    child: Opacity(
                      opacity: progress.abs(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: color, width: 2.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(label.toUpperCase(),
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
