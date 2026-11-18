import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_strings.dart';
import 'ios.dart';

/// Whether the platform has a camera worth offering (mobile only).
bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Prompts the user to pick an image and returns its bytes, or null if
/// cancelled. On mobile it offers camera/gallery; on desktop and web it goes
/// straight to the file picker (no camera). Bytes (not paths) so it works
/// uniformly across platforms and can be base64-stored + synced.
Future<Uint8List?> pickImageBytes(BuildContext context) async {
  ImageSource source = ImageSource.gallery;
  if (_isMobile) {
    final picked = await showIosActionSheet<ImageSource>(
      context,
      options: [
        (CupertinoIcons.camera, context.s.camera, ImageSource.camera),
        (CupertinoIcons.photo_on_rectangle, context.s.gallery, ImageSource.gallery),
      ],
    );
    if (picked == null) return null;
    source = picked;
  }

  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    maxWidth: 1600,
    imageQuality: 80,
  );
  if (file == null) return null;
  return file.readAsBytes();
}
