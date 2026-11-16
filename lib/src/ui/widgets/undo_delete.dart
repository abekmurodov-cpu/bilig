import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../providers/knowledge_providers.dart';

/// "Note deleted · Undo": a delete is one tap away from being taken back.
void showUndoDelete(ScaffoldMessengerState messenger, AppStrings strings,
    KnowledgeListNotifier store, DeletedNotes deleted) {
  if (deleted.notes.isEmpty) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(strings.notesDeleted(deleted.notes.length)),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: strings.undo, onPressed: () => store.restore(deleted)),
    ));
}
