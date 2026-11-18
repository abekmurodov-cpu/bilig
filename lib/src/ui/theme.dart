import 'package:flutter/cupertino.dart';
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
    // iOS everywhere: pages slide in from the right and swipe back, the back
    // button is a chevron.
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final platform in TargetPlatform.values)
        platform: const CupertinoPageTransitionsBuilder(),
    }),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(CupertinoIcons.back, size: 28),
    ),
    // Pushed screens get a small centred title; tabs use [largeTitleBar].
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: dark ? scheme.surface : scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      // The theme's text styles get their sizes later (per locale), so
      // styles set outside textTheme spell out their size.
      titleTextStyle: TextStyle(
          fontFamily: appFont,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: -0.2),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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

/// The top bar of a tab: an iOS large title on the left.
AppBar largeTitleBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) =>
    AppBar(
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(
          fontFamily: appFont,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
          letterSpacing: -0.6),
      title: title,
      actions: actions,
      bottom: bottom,
    );

/// iOS scrolling everywhere: lists bounce at the ends instead of glowing.
class IosScrollBehavior extends MaterialScrollBehavior {
  const IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
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
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
