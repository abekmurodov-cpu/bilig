import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/secret_store.dart';
import '../data/settings_repository.dart';
import '../l10n/app_strings.dart';

/// Bound to the real secure store in `main`; in-memory otherwise (tests).
final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore.memory());

/// Bound to the Hive-backed store in `main`; in-memory otherwise (tests).
final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SettingsRepository.memory());

/// Current theme mode, persisted in the settings box.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  @override
  ThemeMode build() {
    final stored = _settings.getString(SettingsRepository.kThemeMode);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _settings.setString(SettingsRepository.kThemeMode, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Interface language, persisted in the settings box (English by default).
class LanguageNotifier extends Notifier<AppLanguage> {
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  @override
  AppLanguage build() =>
      AppLanguage.fromCode(_settings.getString(SettingsRepository.kLanguage));

  Future<void> set(AppLanguage language) async {
    state = language;
    await _settings.setString(SettingsRepository.kLanguage, language.name);
  }
}

final languageProvider =
    NotifierProvider<LanguageNotifier, AppLanguage>(LanguageNotifier.new);
