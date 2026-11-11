import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'settings_repository.dart';

/// Holds secrets (AI API key, Telegram bot token) in the platform's secure
/// storage: Keychain on Apple platforms, encrypted storage on Android,
/// WebCrypto on the web.
///
/// Values are loaded once at startup and served synchronously from memory.
/// If secure storage is unavailable (it can be on unsigned desktop builds or
/// plain-HTTP web), values fall back to the settings box so the key still
/// works — just without the extra protection.
class SecretStore {
  SecretStore._(this._secure, this._fallback, this._cache);

  /// An in-memory store (tests, and the default before startup wires the
  /// real one).
  SecretStore.memory()
      : _secure = null,
        _fallback = null,
        _cache = {};

  static const String kAiApiKey = 'aiApiKey';
  static const String kAiBackupApiKey = 'aiBackupApiKey';
  static const String kTelegramBotToken = 'telegramBotToken';
  static const List<String> _keys = [kAiApiKey, kAiBackupApiKey, kTelegramBotToken];

  /// Settings-box prefix for values stored by the fallback.
  static const String _fallbackPrefix = 'secret.';

  final FlutterSecureStorage? _secure;
  final SettingsRepository? _fallback;
  final Map<String, String> _cache;

  static Future<SecretStore> open(SettingsRepository fallback) async {
    final secure = FlutterSecureStorage(
      // The data-protection keychain needs a provisioned Keychain Sharing
      // entitlement; the regular keychain doesn't.
      mOptions: !kIsWeb && Platform.isMacOS
          ? const MacOsOptions(usesDataProtectionKeychain: false)
          : MacOsOptions.defaultOptions,
    );
    final cache = <String, String>{};
    for (final key in _keys) {
      String? value;
      try {
        value = await secure.read(key: key);
      } catch (_) {
        // Unavailable; the fallback copy (if any) is used below.
      }
      value ??= fallback.getString('$_fallbackPrefix$key');
      if (value != null && value.isNotEmpty) cache[key] = value;
    }
    return SecretStore._(secure, fallback, cache);
  }

  String? read(String key) => _cache[key];

  /// Stores (or with null, deletes) a secret. Prefers secure storage and
  /// removes any fallback copy once the secure write succeeds.
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    final secure = _secure;
    final fallback = _fallback;
    if (secure == null || fallback == null) return;
    try {
      if (value == null || value.isEmpty) {
        await secure.delete(key: key);
      } else {
        await secure.write(key: key, value: value);
      }
      await fallback.setString('$_fallbackPrefix$key', null);
    } catch (_) {
      await fallback.setString('$_fallbackPrefix$key', value);
    }
  }
}
