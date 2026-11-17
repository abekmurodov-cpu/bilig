import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/anki_import.dart';
import '../data/auto_backup.dart';
import '../data/bilig_file.dart';
import '../data/sample_notes.dart';
import '../l10n/app_strings.dart';
import '../llm/llm_provider.dart';
import '../providers/knowledge_providers.dart';
import 'bulk_add_screen.dart';
import 'settings_screen.dart';
import 'widgets/file_io.dart';

/// Settings → "Your notes": back up and restore, import from Anki or
/// Quizlet, and remove the sample notes.
class DataSection extends ConsumerStatefulWidget {
  const DataSection({super.key});

  @override
  ConsumerState<DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends ConsumerState<DataSection> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() task) async {
    final strings = context.s;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      _say(strings.fileFailed(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
        final strings = context.s;
        final notes = ref.read(notesSortedProvider);
        final images = ref.read(imageStoreProvider);
        final file = BiligFile(
          kind: BiligFileKind.backup,
          notes: notes,
          images: {
            for (final n in notes)
              if (n.hasImage && images.getBase64(n.id) != null)
                n.id: images.getBase64(n.id)!,
          },
        );
        final saved = await saveOrShareFile(
            file.encode(), 'bilig-backup-${_today()}.bilig',
            mimeType: 'application/json');
        if (saved) _say(strings.backupSaved(notes.length));
      });

  Future<void> _restore() => _run(() async {
        final picked = await pickFile('Bilig', const ['bilig', 'json']);
        if (picked == null || !mounted) return;
        await openNotesFile(context, ref, picked.$1, picked.$2);
      });

  Future<void> _importOther() => _run(() async {
        final picked = await pickFile(
            'Anki / Quizlet', const ['apkg', 'colpkg', 'txt', 'csv', 'tsv']);
        if (picked == null || !mounted) return;
        await openNotesFile(context, ref, picked.$1, picked.$2);
      });

  Future<void> _openAutoBackups() => _run(() async {
        final strings = context.s;
        final backups = await AutoBackup.list();
        if (!mounted) return;
        if (backups.isEmpty) {
          _say(strings.noAutoBackups);
          return;
        }
        final local = MaterialLocalizations.of(context);
        final picked = await showDialog<File>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(strings.autoBackups),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(strings.autoBackupsBlurb,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              for (final b in backups)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(local.formatMediumDate(b.date)),
                  onTap: () => Navigator.pop(context, b.file),
                ),
            ],
          ),
        );
        if (picked == null) return;
        final bytes = await AutoBackup.read(picked);
        if (!mounted) return;
        await openNotesFile(context, ref, picked.uri.pathSegments.last, bytes);
      });

  Future<void> _removeSamples() => _run(() async {
        final strings = context.s;
        final n = await ref.read(knowledgeListProvider.notifier).deleteTagged(sampleTags);
        _say(strings.samplesRemoved(n));
      });

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final notes = ref.watch(notesSortedProvider);
    final hasSamples = notes.any(
        (n) => n.tags.any((t) => sampleTags.contains(t.toLowerCase())));
    return SettingsSection(
      title: strings.yourNotes,
      icon: Icons.inventory_2_outlined,
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: Text(strings.exportBackup),
            subtitle: Text(strings.exportBackupBlurb),
            enabled: !_busy && notes.isNotEmpty,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(strings.restoreBackup),
            subtitle: Text(strings.restoreBackupBlurb),
            enabled: !_busy,
            onTap: _restore,
          ),
          ListTile(
            leading: const Icon(Icons.move_to_inbox_outlined),
            title: Text(strings.importAnki),
            subtitle: Text(strings.importAnkiBlurb),
            enabled: !_busy,
            onTap: _importOther,
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(strings.autoBackups),
            subtitle: Text(strings.autoBackupsSubtitle),
            enabled: !_busy,
            onTap: _openAutoBackups,
          ),
          if (hasSamples)
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(strings.removeSamples),
              enabled: !_busy,
              onTap: _removeSamples,
            ),
        ],
      ),
    );
  }
}

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Text files are usually UTF-8; fall back to Latin-1 for old exports.
String _decodeText(Uint8List bytes) {
  try {
    final text = utf8.decode(bytes);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Opens a notes file by its kind: a .bilig backup or shared category is
/// merged in (after asking, for a shared one); an Anki deck or exported text
/// goes to the import screen to pick notes. Used by Settings and by files
/// shared into the app.
Future<void> openNotesFile(
    BuildContext context, WidgetRef ref, String name, Uint8List bytes) async {
  final strings = context.s;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final lower = name.toLowerCase();
  try {
    if (lower.endsWith('.apkg') ||
        lower.endsWith('.colpkg') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.tsv')) {
      final List<NoteDraft> drafts = lower.endsWith('pkg')
          ? await compute(importAnkiPackage, bytes)
          : importDelimitedText(_decodeText(bytes));
      if (drafts.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(strings.nothingToImport)));
        return;
      }
      await navigator.push(MaterialPageRoute(
        builder: (_) => BulkAddScreen(source: BulkSource.import, initialDrafts: drafts),
      ));
      return;
    }
    final file = BiligFile.decode(bytes);
    if (file.kind == BiligFileKind.share && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.addSharedTitle(file.title ?? name)),
          content: Text(strings.addSharedBody(file.notes.length)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.addNotes)),
          ],
        ),
      );
      if (ok != true) return;
    }
    final result = await ref.read(knowledgeListProvider.notifier).importFile(file);
    messenger.showSnackBar(
        SnackBar(content: Text(strings.imported(result.added, result.updated))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(strings.fileFailed(e))));
  }
}
