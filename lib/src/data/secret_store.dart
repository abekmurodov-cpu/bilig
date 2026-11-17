import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'settings_repository.dart';

/// Holds secrets (AI API key, Telegram bot token) in the platform's secure
/// storage: encrypted storage on Android, Keychain on iOS, WebCrypto on the
/// web.
///
/// On macOS they stay in the app's own sandbox container instead. The Mac
/// build isn't signed with an Apple developer certificate, and the Keychain
/// ties an item to the exact build that saved it, so every new build asked
/// for the Mac password again, once per secret. The container is private to
/// Bilig: macOS stops other apps reading it without asking.
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

  /// Set once secrets kept in the macOS Keychain by earlier versions have
  /// been moved to the container.
  static const String _movedFromKeychain = 'secretsMovedFromKeychain';

  final FlutterSecureStorage? _secure;
  final SettingsRepository? _fallback;
  final Map<String, String> _cache;

  static Future<SecretStore> open(SettingsRepository fallback) async {
    if (!kIsWeb && Platform.isMacOS) return _openInContainer(fallback);
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

  static Future<SecretStore> _openInContainer(SettingsRepository settings) async {
    final cache = <String, String>{
      for (final key in _keys)
        if (settings.getString('$_fallbackPrefix$key')?.isNotEmpty ?? false)
          key: settings.getString('$_fallbackPrefix$key')!,
    };
    if (settings.getString(_movedFromKeychain) == null) {
      // One last read from the Keychain (macOS may ask for the password this
      // once), then the secrets live in the container.
      const keychain = FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false));
      for (final key in _keys) {
        if (cache.containsKey(key)) continue;
        try {
          final value = await keychain.read(key: key);
          if (value != null && value.isNotEmpty) {
            cache[key] = value;
            await settings.setString('$_fallbackPrefix$key', value);
          }
        } catch (_) {
          // Denied or unavailable: the student can paste the key again.
        }
      }
      await settings.setString(_movedFromKeychain, '1');
    }
    return SecretStore._(null, settings, cache);
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
    if (fallback == null) return; // in memory only
    if (secure == null) {
      // macOS: the app's container.
      await fallback.setString(
          '$_fallbackPrefix$key', value == null || value.isEmpty ? null : value);
      return;
    }
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
