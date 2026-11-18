import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/share_inbox.dart';
import '../data/auto_backup.dart';
import '../l10n/app_strings.dart';
import '../llm/quiz_prep.dart';
import '../notifications/notification_providers.dart';
import '../platform/due_signals.dart';
import '../providers/navigation.dart';
import '../providers/settings_providers.dart';
import '../providers/knowledge_providers.dart';
import '../sync/sync_providers.dart';
import 'bulk_add_screen.dart';
import 'capture_screen.dart';
import 'data_section.dart';
import 'home_screen.dart';
import 'notes_screen.dart';
import 'widgets/app_logo.dart';
import 'practice/practice_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Top-level navigation: a persistent iOS tab bar over four tabs. Each tab
/// hosts its own [Scaffold] (app bar / FAB), so screens keep their own chrome
/// while sharing the bottom bar. Tab state is kept alive with an [IndexedStack].
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {

  @override
  void initState() {
    super.initState();
    // Best-effort silent pull on startup when a sync backend is attached.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoSync();
      _autoBackup();
      _scheduleSignals();
      ShareInbox.listen(_openShared);
      final initial = await ShareInbox.takeInitial();
      if (initial != null) _openShared(initial);
    });
  }

  /// Shared text or a photo opens the right capture screen: a photo is read
  /// into notes, a short text becomes one note, a longer one is split.
  void _openShared(SharedContent content) {
    if (!mounted) return;
    final image = content.image;
    final text = content.text ?? '';
    final file = content.file;
    if (file != null) {
      openNotesFile(context, ref, content.fileName ?? 'shared.bilig', file);
    } else if (image != null) {
      openBulkAdd(context, BulkSource.photo, image: image);
    } else if (text.length <= 160 && !text.contains('\n')) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CaptureScreen(initialFront: text)));
    } else {
      openBulkAdd(context, BulkSource.text, text: text);
    }
  }

  /// The weekly safety copy, once the notes have loaded.
  Future<void> _autoBackup() async {
    try {
      final notes = await ref.read(knowledgeListProvider.future);
      await AutoBackup.runIfDue(
          notes, ref.read(imageStoreProvider), ref.read(settingsRepositoryProvider));
    } catch (_) {
      // Best effort: a failed copy is tried again next start.
    }
  }

  Future<void> _autoSync() async {
    final controller = ref.read(syncControllerProvider);
    if (controller == null) return;
    try {
      await controller.syncNow();
      if (mounted) ref.invalidate(knowledgeListProvider);
    } catch (_) {
      // Silent — the user can retry from Settings and see the error there.
    }
  }

  static const _tabs = [
    HomeScreen(),
    NotesScreen(),
    PracticeScreen(),
    SettingsScreen(),
  ];

  Timer? _signalTimer;

  @override
  void dispose() {
    _signalTimer?.cancel();
    super.dispose();
  }

  /// Refreshes the Dock badge / home-screen widget shortly after notes
  /// change (a review session changes them many times).
  void _scheduleSignals() {
    _signalTimer?.cancel();
    _signalTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      DueSignals.update(ref.read(notesSortedProvider), context.s);
      // Reminder texts follow the due counts.
      ref.read(reminderProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the background quiz generator alive for the whole session.
    ref.listen(quizPrepProvider, (_, _) {});
    ref.listen(knowledgeListProvider, (_, _) => _scheduleSignals());
    final tab = ref.watch(shellTabProvider);
    final stack = IndexedStack(
      index: tab,
      children: [
        // Hidden tabs stay alive but stop animating (the swaying trees).
        for (var i = 0; i < _tabs.length; i++)
          TickerMode(enabled: i == tab, child: _tabs[i]),
      ],
    );
    return _Shortcuts(
      onCapture: _openCapture,
      child: _DropZone(
        onDrop: _openDropped,
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= wideLayout
              ? Scaffold(
                  body: Row(
                    children: [
                      _Rail(tab: tab, extended: box.maxWidth >= 1200, onCapture: _openCapture),
                      const VerticalDivider(width: 1),
                      Expanded(child: stack),
                    ],
                  ),
                )
              : Scaffold(body: stack, bottomNavigationBar: _BottomBar(tab: tab, onCapture: _openCapture)),
        ),
      ),
    );
  }

  /// A new note slides up as a sheet, like composing on iOS.
  void _openCapture() => Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => const CaptureScreen()));

  /// Files dropped on the window: a picture becomes notes, a notes file or
  /// deck is opened, and text is split into notes.
  Future<void> _openDropped(List<(String, Uint8List)> files) async {
    for (final (name, bytes) in files) {
      if (!mounted) return;
      final lower = name.toLowerCase();
      if (RegExp(r'\.(png|jpe?g|webp|heic|gif)$').hasMatch(lower)) {
        await openBulkAdd(context, BulkSource.photo, image: bytes);
      } else if (RegExp(r'\.(md|markdown)$').hasMatch(lower)) {
        await openBulkAdd(context, BulkSource.text, text: utf8.decode(bytes, allowMalformed: true));
      } else {
        await openNotesFile(context, ref, name, bytes);
      }
    }
  }
}

/// Wider than this (a Mac window, a tablet), the tabs move to a side rail.
const double wideLayout = 840;

/// The iOS tab bar: icons over small labels on a translucent strip with a
/// hairline on top, the chosen tab in the brand colour.
class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.tab, required this.onCapture});

  final int tab;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    void go(int i) {
      if (i != tab) HapticFeedback.selectionClick();
      ref.read(shellTabProvider.notifier).go(i);
    }

    Widget item(int i, IconData icon, IconData selectedIcon, String label) =>
        _TabItem(
          icon: i == tab ? selectedIcon : icon,
          label: label,
          color: i == tab ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.85),
          selected: i == tab,
          onTap: () => go(i),
        );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (dark ? scheme.surfaceContainer : scheme.surfaceContainerLowest)
                .withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: dark ? 0.5 : 0.8),
                  width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 54,
              child: Row(
                children: [
                  item(0, CupertinoIcons.house, CupertinoIcons.house_fill, strings.navHome),
                  item(1, CupertinoIcons.book, CupertinoIcons.book_fill, strings.navNotes),
                  _TabItem(
                    icon: CupertinoIcons.plus_circle_fill,
                    iconSize: 34,
                    label: strings.capture,
                    color: scheme.primary,
                    selected: false,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onCapture();
                    },
                  ),
                  item(2, CupertinoIcons.bolt, CupertinoIcons.bolt_fill, strings.navPractice),
                  item(3, CupertinoIcons.gear_alt, CupertinoIcons.gear_alt_fill,
                      strings.navSettings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.iconSize = 25,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 30,
                  child: Center(child: Icon(icon, size: iconSize, color: color)),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: appFont,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// The tabs down the side on wide screens, with Capture on top.
class _Rail extends ConsumerWidget {
  const _Rail({required this.tab, required this.extended, required this.onCapture});

  final int tab;
  final bool extended;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 210,
      backgroundColor: scheme.surfaceContainerLow,
      selectedIndex: tab,
      onDestinationSelected: (i) => ref.read(shellTabProvider.notifier).go(i),
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 36),
                if (extended) ...[
                  const SizedBox(width: 10),
                  Text('Bilig', style: Theme.of(context).textTheme.titleLarge),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Tooltip(
              message: '${strings.capture}  (${_mod()}N)',
              child: extended
                  ? FloatingActionButton.extended(
                      heroTag: 'capture',
                      elevation: 0,
                      onPressed: onCapture,
                      icon: const Icon(Icons.add),
                      label: Text(strings.capture),
                    )
                  : FloatingActionButton(
                      heroTag: 'capture',
                      elevation: 0,
                      onPressed: onCapture,
                      child: const Icon(Icons.add),
                    ),
            ),
          ],
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.house),
          selectedIcon: const Icon(CupertinoIcons.house_fill),
          label: Text(strings.navHome),
        ),
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.book),
          selectedIcon: const Icon(CupertinoIcons.book_fill),
          label: Text(strings.navNotes),
        ),
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.bolt),
          selectedIcon: const Icon(CupertinoIcons.bolt_fill),
          label: Text(strings.navPractice),
        ),
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.gear_alt),
          selectedIcon: const Icon(CupertinoIcons.gear_alt_fill),
          label: Text(strings.navSettings),
        ),
      ],
    );
  }
}

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// "⌘" on a Mac, "Ctrl+" elsewhere.
String _mod() => _isMac ? '⌘' : 'Ctrl+';

/// Keyboard shortcuts anywhere in the app: ⌘N new note, ⌘F search notes,
/// ⌘1–4 switch tabs (Ctrl on other systems).
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts({required this.child, required this.onCapture});

  final Widget child;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SingleActivator key(LogicalKeyboardKey k) =>
        SingleActivator(k, meta: _isMac, control: !_isMac);
    void tab(int i) => ref.read(shellTabProvider.notifier).go(i);
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.keyN): onCapture,
        key(LogicalKeyboardKey.keyF): () {
          tab(ShellTab.notes);
          ref.read(notesSearchFocusProvider.notifier).request();
        },
        key(LogicalKeyboardKey.digit1): () => tab(ShellTab.home),
        key(LogicalKeyboardKey.digit2): () => tab(ShellTab.notes),
        key(LogicalKeyboardKey.digit3): () => tab(ShellTab.practice),
        key(LogicalKeyboardKey.digit4): () => tab(ShellTab.settings),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// On desktops, files can be dropped on the window to make notes.
class _DropZone extends StatefulWidget {
  const _DropZone({required this.child, required this.onDrop});

  final Widget child;
  final Future<void> Function(List<(String, Uint8List)> files) onDrop;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _over = false;

  static bool get _desktop =>
      !kIsWeb &&
      const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}
          .contains(defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (details) async {
        setState(() => _over = false);
        final files = [
          for (final f in details.files) (f.name, await f.readAsBytes()),
        ];
        await widget.onDrop(files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: scheme.primary.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined, size: 40, color: scheme.primary),
                        const SizedBox(height: 8),
                        Text(context.s.dropToAdd,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(context.s.dropKinds,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
