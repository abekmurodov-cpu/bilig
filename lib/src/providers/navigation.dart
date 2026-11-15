import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bottom-bar tab on screen, so any screen can send the student to
/// another tab ("See all" on Home opens Notes).
class ShellTab extends Notifier<int> {
  static const home = 0, notes = 1, practice = 2, settings = 3;

  @override
  int build() => home;

  void go(int tab) => state = tab;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

/// A filter for Notes to apply when it shows next: category names and topic
/// keys (see `topicKey`). Notes takes it and clears it.
class NotesFilterRequest extends Notifier<Set<String>?> {
  @override
  Set<String>? build() => null;

  void show(Set<String> filter) => state = {...filter};

  void clear() => state = null;
}

final notesFilterRequestProvider =
    NotifierProvider<NotesFilterRequest, Set<String>?>(NotesFilterRequest.new);
