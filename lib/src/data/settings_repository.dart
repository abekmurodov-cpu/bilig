import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Small key/value store for app preferences and attached-service credentials
/// (theme, AI service + model, Telegram bot config, practice defaults; AI keys
/// themselves live in SecretStore). Backed by its
/// own Hive box so it stays independent of the knowledge-items store and works
/// the same on mobile and web.
class SettingsRepository {
  SettingsRepository(Box this._box) : _memory = null;

  /// Kept in memory only (tests, and before storage is opened).
  SettingsRepository.memory()
      : _box = null,
        _memory = {};

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
  static const String kAiBackupService = 'aiBackupService';
  static const String kAiBackupModel = 'aiBackupModel';
  static const String kAiBackupBaseUrl = 'aiBackupBaseUrl';
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
  static const String kVoiceMode = 'voiceMode';
  static const String kExams = 'exams';
  static const String kOnboarded = 'onboarded';
  static const String kActivity = 'activity';
  static const String kVoiceLocale = 'voiceLocale';

  final Box? _box;
  final Map<String, Object?>? _memory;

  Object? _get(String key) => _box != null ? _box.get(key) : _memory![key];

  Future<void> _put(String key, Object? value) async {
    if (_box != null) {
      value == null ? await _box.delete(key) : await _box.put(key, value);
    } else {
      value == null ? _memory!.remove(key) : _memory![key] = value;
    }
  }

  static Future<SettingsRepository> open() async {
    final box = await Hive.openBox(boxName);
    return SettingsRepository(box);
  }

  String? getString(String key) => _get(key) as String?;

  Future<void> setString(String key, String? value) =>
      _put(key, value == null || value.isEmpty ? null : value);

  int? getInt(String key) => (_get(key) as num?)?.toInt();

  Future<void> setInt(String key, int? value) => _put(key, value);
}
