import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/anki_import.dart';
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
        final strings = context.s;
        final picked = await pickFile('Bilig', const ['bilig', 'json']);
        if (picked == null) return;
        final file = BiligFile.decode(picked.$2);
        final result =
            await ref.read(knowledgeListProvider.notifier).importFile(file);
        _say(strings.imported(result.added, result.updated));
      });

  Future<void> _importOther() => _run(() async {
        final strings = context.s;
        final navigator = Navigator.of(context);
        final picked = await pickFile(
            'Anki / Quizlet', const ['apkg', 'colpkg', 'txt', 'csv', 'tsv']);
        if (picked == null) return;
        final (name, bytes) = picked;
        final lower = name.toLowerCase();
        final List<NoteDraft> drafts;
        if (lower.endsWith('.apkg') || lower.endsWith('.colpkg')) {
          drafts = await compute(importAnkiPackage, bytes);
        } else {
          drafts = importDelimitedText(_decodeText(bytes));
        }
        if (drafts.isEmpty) {
          _say(strings.nothingToImport);
          return;
        }
        await navigator.push(MaterialPageRoute(
          builder: (_) => BulkAddScreen(source: BulkSource.import, initialDrafts: drafts),
        ));
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
