import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/knowledge_item.dart';
import 'bilig_file.dart';
import 'image_store.dart';
import 'settings_repository.dart';

/// A weekly copy of every note (with images and progress) kept inside the
/// app, so a slip — or a broken update — never costs the student their notes.
/// The newest [keep] copies are kept.
class AutoBackup {
  AutoBackup._();

  static const Duration every = Duration(days: 7);
  static const int keep = 4;
  static const String _prefix = 'bilig-auto-';

  static Future<Directory> _folder() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/Backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes a backup if the last one is a week old (or there is none).
  /// Returns whether one was written.
  static Future<bool> runIfDue(List<KnowledgeItem> notes, ImageStore images,
      SettingsRepository settings, {DateTime? now}) async {
    if (notes.isEmpty) return false;
    final at = now ?? DateTime.now();
    final last = DateTime.tryParse(settings.getString(SettingsRepository.kLastAutoBackup) ?? '');
    if (last != null && at.difference(last) < every) return false;
    final file = BiligFile(
      kind: BiligFileKind.backup,
      notes: notes,
      images: {
        for (final n in notes)
          if (n.hasImage && images.getBase64(n.id) != null) n.id: images.getBase64(n.id)!,
      },
    );
    final dir = await _folder();
    final name = '$_prefix${at.toIso8601String().substring(0, 10)}.bilig';
    await File('${dir.path}/$name').writeAsBytes(file.encode(), flush: true);
    await settings.setString(SettingsRepository.kLastAutoBackup, at.toIso8601String());
    final old = await list();
    for (final b in old.skip(keep)) {
      await b.file.delete();
    }
    return true;
  }

  /// The backups kept, newest first.
  static Future<List<({File file, DateTime date})>> list() async {
    final dir = await _folder();
    final out = <({File file, DateTime date})>[];
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (!name.startsWith(_prefix) || !name.endsWith('.bilig')) continue;
      final date = DateTime.tryParse(name.substring(_prefix.length, name.length - 6));
      if (date != null) out.add((file: f, date: date));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  static Future<Uint8List> read(File file) => file.readAsBytes();
}
