import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Small key/value store for app preferences and attached-service credentials
/// (theme, AI service + model, Telegram bot config, practice defaults; AI keys
/// themselves live in SecretStore). Backed by its
/// own Hive box so it stays independent of the knowledge-items store and works
/// the same on mobile and web.
class SettingsRepository {
  SettingsRepository(this._box);

  static const String boxName = 'settings';

  // Keys.
  static const String kThemeMode = 'themeMode';
  static const String kLanguage = 'language';
  /// Legacy (Gemini-only) AI settings; migrated to the kAi* keys on load.
  static const String kGeminiApiKey = 'geminiApiKey';
  static const String kGeminiModel = 'geminiModel';
  static const String kAiService = 'aiService';
  static const String kAiModel = 'aiModel';
  static const String kAiBaseUrl = 'aiBaseUrl';
  static const String kAiModels = 'aiModels';
  /// Legacy location of the bot token; now in SecretStore (migrated on load).
  static const String kTelegramBotToken = 'telegramBotToken';
  static const String kTelegramChatId = 'telegramChatId';
  static const String kTelegramUser = 'telegramUser';
  static const String kTelegramPinnedMessageId = 'telegramPinnedMessageId';
  static const String kPracticeMethod = 'practiceMethod';
  static const String kPracticeScope = 'practiceScope';
  static const String kReminderEnabled = 'reminderEnabled';
  static const String kReminderHour = 'reminderHour';
  static const String kReminderMinute = 'reminderMinute';

  final Box _box;

  static Future<SettingsRepository> open() async {
    final box = await Hive.openBox(boxName);
    return SettingsRepository(box);
  }

  String? getString(String key) => _box.get(key) as String?;

  Future<void> setString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _box.delete(key);
    } else {
      await _box.put(key, value);
    }
  }

  int? getInt(String key) => (_box.get(key) as num?)?.toInt();

  Future<void> setInt(String key, int? value) async {
    if (value == null) {
      await _box.delete(key);
    } else {
      await _box.put(key, value);
    }
  }
}
