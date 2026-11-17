import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Saves [bytes] as [name]: a save dialog on desktop, the share sheet on
/// phones and the web (save to Files/Drive, send to Telegram…). Returns false
/// when the student cancelled.
Future<bool> saveOrShareFile(Uint8List bytes, String name,
    {String mimeType = 'application/octet-stream'}) async {
  if (_isMobile || kIsWeb) {
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
      fileNameOverrides: [name],
      downloadFallbackEnabled: true,
    ));
    return result.status != ShareResultStatus.dismissed;
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return false;
  await File(location.path).writeAsBytes(bytes);
  return true;
}

/// Lets the student pick a file with one of [extensions] (on Android any
/// file, since it doesn't know types like .bilig or .apkg). Returns its name
/// and bytes, or null when cancelled.
Future<(String, Uint8List)?> pickFile(String label, List<String> extensions) async {
  final file = await openFile(acceptedTypeGroups: [
    _isMobile
        ? const XTypeGroup(label: 'any')
        : XTypeGroup(label: label, extensions: extensions),
  ]);
  if (file == null) return null;
  return (file.name, await file.readAsBytes());
}
