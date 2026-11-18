import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Bilig's indigo.
const Color brandSeed = Color(0xFF5B6CF0);

/// The app's typeface (bundled, so the Mac and phones look alike and
/// Uzbek ʻ and Cyrillic render the same everywhere).
const String appFont = 'Inter';

/// The serif of the note paper.
const String paperFont = 'SourceSerif';

/// Corner radius of cards, sheets and grouped sections.
const double cardRadius = 18;

/// Corner radius of fields and buttons.
const double controlRadius = 14;

/// The app's look: quiet tinted surfaces instead of shadows, rounded cards,
/// filled fields, firm headings and roomy buttons.
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brandSeed, brightness: brightness);
  final dark = brightness == Brightness.dark;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: appFont);
  final text = base.textTheme;
  final controlShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius));
  const buttonSize = Size(64, 48);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? scheme.surface : scheme.surfaceContainerLowest,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: dark ? scheme.surface : scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      // The theme's text styles get their sizes later (per locale), so
      // styles set outside textTheme spell out their size.
      titleTextStyle: TextStyle(
          fontFamily: appFont,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: -0.3),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(color: scheme.error),
      ),
      floatingLabelStyle: TextStyle(color: scheme.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        shape: controlShape,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: controlShape,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: controlShape),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: controlShape,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
      iconColor: scheme.onSurfaceVariant,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontFamily: appFont,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

/// The card a practice question sits on: lifted a little off the page.
BoxDecoration practiceCardDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    boxShadow: [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: dark ? 0.3 : 0.06),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

/// Keeps content to a comfortable reading width on wide windows (a Mac, a
/// tablet), centred; on a phone it changes nothing.
///
/// The empty margins beside it still scroll what's inside (mouse wheel and
/// trackpad), so scrolling doesn't seem to stop working there. Plain lists
/// should prefer [ReadableBuilder], which makes the list itself full-width.
class ReadableWidth extends StatefulWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  State<ReadableWidth> createState() => _ReadableWidthState();
}

class _ReadableWidthState extends State<ReadableWidth> {
  final _content = GlobalKey();

  /// The outermost vertical list inside, if any.
  ScrollPosition? _scrollable() {
    ScrollPosition? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement &&
          e.state is ScrollableState &&
          (e.state as ScrollableState).position.axis == Axis.vertical) {
        found = (e.state as ScrollableState).position;
        return;
      }
      e.visitChildren(visit);
    }

    _content.currentContext?.visitChildElements(visit);
    return found;
  }

  void _scrollBy(double delta) {
    final position = _scrollable();
    if (position == null || delta == 0) return;
    position.pointerScroll(delta);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final side = box.maxWidth.isFinite
            ? ((box.maxWidth - widget.maxWidth) / 2).clamp(0.0, double.infinity)
            : 0.0;
        bool inMargin(Offset p) => p.dx < side || p.dx > box.maxWidth - side;
        final content = Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            key: _content,
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: widget.child,
          ),
        );
        if (side == 0) return content;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && inMargin(e.localPosition)) {
              _scrollBy(e.scrollDelta.dy);
            }
          },
          onPointerPanZoomUpdate: (e) {
            // Trackpad: fingers up scroll down.
            if (inMargin(e.localPosition)) _scrollBy(-e.panDelta.dy);
          },
          child: content,
        );
      });
}

/// For a list on a wide window: hands [builder] the side padding that keeps
/// the list's content at a readable width in the middle, while the list
/// itself spans the whole width, so scrolling works over the margins too and
/// the scrollbar sits at the window's edge. On a phone the padding is zero.
class ReadableBuilder extends StatelessWidget {
  const ReadableBuilder({super.key, required this.builder, this.maxWidth = 760});

  final Widget Function(BuildContext context, EdgeInsets gutter) builder;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final side = box.maxWidth.isFinite
            ? ((box.maxWidth - maxWidth) / 2).clamp(0.0, double.infinity)
            : 0.0;
        return builder(context, EdgeInsets.symmetric(horizontal: side));
      });
}
