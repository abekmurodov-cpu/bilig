import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/share_inbox.dart';
import '../l10n/app_strings.dart';
import '../llm/quiz_prep.dart';
import '../platform/due_signals.dart';
import '../providers/knowledge_providers.dart';
import '../sync/sync_providers.dart';
import 'bulk_add_screen.dart';
import 'capture_screen.dart';
import 'data_section.dart';
import 'home_screen.dart';
import 'notes_screen.dart';
import 'practice/practice_screen.dart';
import 'settings_screen.dart';

/// Top-level navigation: a persistent [NavigationBar] over four tabs. Each tab
/// hosts its own [Scaffold] (app bar / FAB), so screens keep their own chrome
/// while sharing the bottom bar. Tab state is kept alive with an [IndexedStack].
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Best-effort silent pull on startup when a sync backend is attached.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoSync();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the background quiz generator alive for the whole session.
    ref.listen(quizPrepProvider, (_, _) {});
    ref.listen(knowledgeListProvider, (_, _) => _scheduleSignals());
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: context.s.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.park_outlined),
            selectedIcon: Icon(Icons.park),
            label: context.s.navNotes,
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: context.s.navPractice,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: context.s.navSettings,
          ),
        ],
      ),
    );
  }
}
