/// Which wire format a service speaks.
enum AiApi { gemini, openAi, anthropic }

/// The AI services a student can connect with their own key. Most speak the
/// OpenAI format, so one connector covers them with a different base URL.
enum AiService {
  gemini(
    label: 'Gemini (Google)',
    api: AiApi.gemini,
    keyUrl: 'https://aistudio.google.com/apikey',
    freeTier: true,
    defaultModel: 'gemini-3.1-flash-lite',
    prefer: [r'^gemini-[\d.]+-flash-lite$', r'^gemini-[\d.]+-flash$', r'^gemini-'],
  ),
  openai(
    label: 'ChatGPT (OpenAI)',
    api: AiApi.openAi,
    baseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    prefer: [r'^gpt-[\d.]+-mini$', r'^gpt-.*mini$', r'^gpt-'],
  ),
  claude(
    label: 'Claude (Anthropic)',
    api: AiApi.anthropic,
    keyUrl: 'https://console.anthropic.com/settings/keys',
    // Short note/quiz tasks don't need a bigger model; Haiku keeps a
    // student's key cheap.
    defaultModel: 'claude-haiku-5-5',
    prefer: [r'^claude-haiku-\d', r'^claude-'],
  ),
  deepseek(
    label: 'DeepSeek',
    api: AiApi.openAi,
    baseUrl: 'https://api.deepseek.com/v1',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    defaultModel: 'deepseek-chat',
  ),
  groq(
    label: 'Groq',
    api: AiApi.openAi,
    baseUrl: 'https://api.groq.com/openai/v1',
    keyUrl: 'https://console.groq.com/keys',
    freeTier: true,
    prefer: [r'llama.*versatile', r'gpt-oss', r'llama', r'qwen'],
  ),
  openrouter(
    label: 'OpenRouter',
    api: AiApi.openAi,
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/keys',
    freeTier: true,
    prefer: [r'(llama|gemini|deepseek|qwen|gpt-oss|mistral).*:free$', r':free$'],
  ),
  mistral(
    label: 'Mistral',
    api: AiApi.openAi,
    baseUrl: 'https://api.mistral.ai/v1',
    keyUrl: 'https://console.mistral.ai/api-keys',
    defaultModel: 'mistral-small-latest',
  ),
  xai(
    label: 'Grok (xAI)',
    api: AiApi.openAi,
    baseUrl: 'https://api.x.ai/v1',
    keyUrl: 'https://console.x.ai',
    prefer: [r'^grok-.*mini', r'^grok-.*fast', r'^grok-'],
  ),

  /// Any other OpenAI-compatible server, including AI running on the user's
  /// own computer (Ollama, LM Studio). The user supplies the address.
  custom(label: 'Other / local (OpenAI-compatible)', api: AiApi.openAi);

  const AiService({
    required this.label,
    required this.api,
    this.baseUrl,
    this.keyUrl,
    this.freeTier = false,
    this.defaultModel,
    this.prefer = const [],
  });

  final String label;
  final AiApi api;

  /// OpenAI-format endpoint root (ending in `/v1`); null for [custom], whose
  /// address the user types.
  final String? baseUrl;

  /// Where to create a key.
  final String? keyUrl;

  /// Usable without paying, within the service's limits.
  final bool freeTier;

  /// Used when present in the key's model list (or when the list can't be
  /// fetched).
  final String? defaultModel;

  /// Model-id patterns in order of preference, for picking a sensible model
  /// from the key's list when [defaultModel] isn't available.
  final List<String> prefer;

  /// Local servers usually need no key.
  bool get needsKey => this != AiService.custom;

  static AiService fromName(String? name) => AiService.values
      .firstWhere((s) => s.name == name, orElse: () => AiService.gemini);
}

/// What a pasted key's prefix says about its service.
class KeyGuess {
  const KeyGuess(this.candidates);

  /// Services the key could belong to: empty when unrecognized, one when
  /// certain, several when the prefix is shared (a plain `sk-` key).
  final List<AiService> candidates;

  AiService? get service => candidates.length == 1 ? candidates.single : null;
}

KeyGuess guessService(String key) {
  final k = key.trim();
  if (k.startsWith('AIza')) return const KeyGuess([AiService.gemini]);
  if (k.startsWith('sk-ant-')) return const KeyGuess([AiService.claude]);
  if (k.startsWith('sk-or-')) return const KeyGuess([AiService.openrouter]);
  if (k.startsWith('gsk_')) return const KeyGuess([AiService.groq]);
  if (k.startsWith('xai-')) return const KeyGuess([AiService.xai]);
  if (k.startsWith('sk-proj-') || k.startsWith('sk-svcacct-')) {
    return const KeyGuess([AiService.openai]);
  }
  if (k.startsWith('sk-')) {
    return const KeyGuess([AiService.openai, AiService.deepseek]);
  }
  return const KeyGuess([]);
}

final _notChat = RegExp(
  r'embed|whisper|tts|audio|image|dall-e|moderation|transcribe|realtime|'
  r'guard|rerank|ocr|search|computer-use|aqa|imagen|veo|lyria|-live|'
  r'native-audio|robotics|sora|speech|codex|instruct-only',
  caseSensitive: false,
);

/// Whether a model id looks like a text chat model (not embeddings, speech,
/// image generation, moderation, ...).
bool isChatModelId(String id) => !_notChat.hasMatch(id);

/// The model to use for [service] given the ids its key can access.
String? recommendedModel(AiService service, List<String> ids) {
  final chat = ids.where(isChatModelId).toList();
  if (service.defaultModel != null &&
      (chat.isEmpty || chat.contains(service.defaultModel))) {
    return service.defaultModel;
  }
  if (chat.isEmpty) return null;
  bool unstable(String id) => RegExp(r'preview|exp|beta').hasMatch(id);
  for (final stableOnly in [true, false]) {
    for (final pattern in service.prefer) {
      final re = RegExp(pattern);
      final matches = chat
          .where((id) => re.hasMatch(id) && (!stableOnly || !unstable(id)))
          .toList()
        ..sort();
      // Ids sort roughly by version, so the last match is usually newest.
      if (matches.isNotEmpty) return matches.last;
    }
  }
  return chat.first;
}
