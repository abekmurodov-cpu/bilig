import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/secret_store.dart';
import '../data/settings_repository.dart';
import '../providers/settings_providers.dart';
import 'ai_services.dart';
import 'anthropic_provider.dart';
import 'gemini_provider.dart';
import 'http_llm.dart';
import 'llm_provider.dart';
import 'openai_compatible_provider.dart';

/// Bound to the real secure store in `main`; in-memory otherwise (tests).
final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore.memory());

/// One connected AI: which service, which model, and how to reach it.
class AiConfig {
  const AiConfig({
    required this.service,
    required this.model,
    this.apiKey = '',
    this.baseUrl,
  });

  final AiService service;
  final String model;
  final String apiKey;

  /// Only for [AiService.custom]; other services have a fixed address.
  final String? baseUrl;

  String? get endpoint => service.baseUrl ?? baseUrl;

  AiConfig withModel(String model) =>
      AiConfig(service: service, model: model, apiKey: apiKey, baseUrl: baseUrl);
}

/// Builds the connector for [config].
HttpLlm createLlm(AiConfig config, {http.Client? client}) {
  return switch (config.service.api) {
    AiApi.gemini =>
      GeminiProvider(apiKey: config.apiKey, model: config.model, client: client),
    AiApi.anthropic =>
      AnthropicProvider(apiKey: config.apiKey, model: config.model, client: client),
    AiApi.openAi => OpenAiCompatibleProvider(
        serviceName: config.service == AiService.custom
            ? 'AI server'
            : config.service.label,
        baseUrl: config.endpoint ?? '',
        apiKey: config.apiKey,
        model: config.model,
        extraHeaders: config.service == AiService.openrouter
            ? const {'X-Title': 'Bilig'}
            : const {},
        client: client,
      ),
  };
}

/// The connected AI (null when none), persisted across launches. The key
/// lives in [SecretStore]; everything else in settings.
class AiConfigNotifier extends Notifier<AiConfig?> {
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);
  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  AiConfig? build() {
    final legacy = _migrateLegacyGemini();
    if (legacy != null) return legacy;
    final serviceName = _settings.getString(SettingsRepository.kAiService);
    final model = _settings.getString(SettingsRepository.kAiModel);
    if (serviceName == null || model == null) return null;
    final service = AiService.fromName(serviceName);
    final key = _secrets.read(SecretStore.kAiApiKey) ?? '';
    if (service.needsKey && key.isEmpty) return null;
    return AiConfig(
      service: service,
      model: model,
      apiKey: key,
      baseUrl: _settings.getString(SettingsRepository.kAiBaseUrl),
    );
  }

  /// Before multi-provider support only a Gemini key + model were stored, in
  /// plain settings. Move them over (the key into secure storage) once, and
  /// return the migrated config.
  AiConfig? _migrateLegacyGemini() {
    final legacyKey = _settings.getString(SettingsRepository.kGeminiApiKey);
    if (legacyKey == null ||
        _settings.getString(SettingsRepository.kAiService) != null) {
      return null;
    }
    final model = _settings.getString(SettingsRepository.kGeminiModel) ??
        AiService.gemini.defaultModel!;
    // The disk writes finish in the background; this session uses the
    // returned config directly.
    unawaited(() async {
      await _secrets.write(SecretStore.kAiApiKey, legacyKey);
      await _settings.setString(SettingsRepository.kAiService, AiService.gemini.name);
      await _settings.setString(SettingsRepository.kAiModel, model);
      await _settings.setString(SettingsRepository.kGeminiApiKey, null);
      await _settings.setString(SettingsRepository.kGeminiModel, null);
    }());
    return AiConfig(service: AiService.gemini, model: model, apiKey: legacyKey);
  }

  /// Connects [config]; [models] is the key's model list, cached for the
  /// model picker.
  Future<void> attach(AiConfig config, {List<String> models = const []}) async {
    await _secrets.write(SecretStore.kAiApiKey, config.apiKey);
    await _settings.setString(SettingsRepository.kAiService, config.service.name);
    await _settings.setString(SettingsRepository.kAiModel, config.model);
    await _settings.setString(SettingsRepository.kAiBaseUrl, config.baseUrl);
    await setModels(models);
    state = config;
  }

  Future<void> setModel(String model) async {
    final current = state;
    if (current == null) return;
    await _settings.setString(SettingsRepository.kAiModel, model);
    state = current.withModel(model);
  }

  Future<void> detach() async {
    await _secrets.write(SecretStore.kAiApiKey, null);
    for (final key in [
      SettingsRepository.kAiService,
      SettingsRepository.kAiModel,
      SettingsRepository.kAiBaseUrl,
      SettingsRepository.kAiModels,
    ]) {
      await _settings.setString(key, null);
    }
    state = null;
  }

  /// The cached model list for the picker.
  List<String> get models {
    final raw = _settings.getString(SettingsRepository.kAiModels);
    if (raw == null) return const [];
    try {
      return [for (final m in jsonDecode(raw) as List) '$m'];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setModels(List<String> models) => _settings.setString(
      SettingsRepository.kAiModels,
      models.isEmpty ? null : jsonEncode(models.where(isChatModelId).toList()..sort()));
}

final aiConfigProvider =
    NotifierProvider<AiConfigNotifier, AiConfig?>(AiConfigNotifier.new);

/// The active LLM, or null when no AI is connected. UI features that use the
/// LLM watch this and hide/fall back when it is null.
final llmProvider = Provider<LlmProvider?>((ref) {
  final config = ref.watch(aiConfigProvider);
  return config == null ? null : createLlm(config);
});
