import 'package:flutter/services.dart';

/// Text or a photo another app shared into Bilig: Android's share sheet, or
/// "New Bilig Note" in the macOS Services menu.
class SharedContent {
  const SharedContent({this.text, this.image});

  final String? text;
  final Uint8List? image;

  static SharedContent? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] as String?)?.trim();
    final image = raw['image'];
    final content = SharedContent(
      text: text == null || text.isEmpty ? null : text,
      image: image is Uint8List && image.isNotEmpty ? image : null,
    );
    return content.text == null && content.image == null ? null : content;
  }
}

/// Receives shared content from the platform side.
class ShareInbox {
  static const _channel = MethodChannel('bilig/share');

  /// What was shared to start the app, if anything (once).
  static Future<SharedContent?> takeInitial() async {
    try {
      return SharedContent.fromChannel(await _channel.invokeMethod('takeInitial'));
    } on MissingPluginException {
      return null; // Platforms without sharing (web, tests).
    } on PlatformException {
      return null;
    }
  }

  /// Calls [onShared] for content shared while the app is running.
  static void listen(void Function(SharedContent content) onShared) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'shared') return;
      final content = SharedContent.fromChannel(call.arguments);
      if (content != null) onShared(content);
    });
  }
}
