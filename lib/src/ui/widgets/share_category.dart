import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/bilig_file.dart';
import '../../l10n/app_strings.dart';
import '../../models/knowledge_item.dart';
import '../../providers/knowledge_providers.dart';
import '../../sync/sync_providers.dart';
import 'category_tree.dart';
import 'file_io.dart';

/// Lets a student give one category to classmates: as a .bilig file (saved
/// or sent through any app), or posted to their Telegram chat to forward.
/// The file carries the notes, their questions, highlights and images, but
/// none of the student's own progress.
Future<void> showShareCategory(
    BuildContext context, String category, List<KnowledgeItem> notes) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ShareSheet(category: category, notes: notes),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.category, required this.notes});

  final String category;
  final List<KnowledgeItem> notes;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _busy = false;

  String get _title => categoryDisplayName(context, widget.category);

  BiligFile _file() {
    final images = ref.read(imageStoreProvider);
    return BiligFile(
      kind: BiligFileKind.share,
      title: _title,
      notes: [for (final n in widget.notes) BiligFile.withoutProgress(n)],
      images: {
        for (final n in widget.notes)
          if (n.hasImage && images.getBase64(n.id) != null) n.id: images.getBase64(n.id)!,
      },
    );
  }

  String get _fileName =>
      '${_title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-').trim()}.bilig';

  Future<void> _run(Future<String?> Function() task) async {
    final strings = context.s;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    String? message;
    try {
      message = await task();
    } catch (e) {
      message = strings.fileFailed(e);
    }
    if (!mounted) return;
    navigator.pop();
    if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final telegram = ref.watch(telegramServiceProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${strings.shareCategory}: $_title',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (_busy) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(strings.shareAsFile),
            subtitle: Text(strings.shareAsFileBlurb),
            enabled: !_busy,
            onTap: () => _run(() async {
              await saveOrShareFile(_file().encode(), _fileName,
                  mimeType: 'application/octet-stream');
              return null;
            }),
          ),
          if (telegram != null)
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: Text(strings.sendToTelegram),
              subtitle: Text(strings.sendToTelegramBlurb),
              enabled: !_busy,
              onTap: () => _run(() async {
                await telegram.sendFile(_file().encode(), _fileName,
                    caption: strings.shareCaption(_title, widget.notes.length));
                return strings.sentToTelegram(_title);
              }),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
