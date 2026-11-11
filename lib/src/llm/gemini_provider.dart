import 'dart:convert';

import 'http_llm.dart';
import 'llm_provider.dart';

/// [LlmProvider] backed by Google's Gemini REST API, using a user-supplied API
/// key (stored locally, never bundled). Calls the `generateContent` endpoint.
class GeminiProvider extends HttpLlm {
  GeminiProvider({
    required this.apiKey,
    this.model = 'gemini-2.5-flash',
    super.client,
    super.sleep,
  });

  final String apiKey;
  final String model;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  @override
  String get displayName => 'Gemini ($model)';

  @override
  Future<String> send(String prompt, {required bool json}) async {
    final uri = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');
    final generationConfig = <String, Object>{
      if (json) 'responseMimeType': 'application/json',
      // 2.5 Flash "thinks" by default, which costs tokens these short tasks
      // don't need.
      if (model.startsWith('gemini-2.5-flash'))
        'thinkingConfig': {'thinkingBudget': 0},
    };
    final resp = await guard(client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        if (generationConfig.isNotEmpty) 'generationConfig': generationConfig,
      }),
    ));
    if (resp.statusCode != 200) throw errorFor(resp.statusCode, resp.body);

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } on FormatException {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Gemini sent an unreadable reply');
    }
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Gemini returned no answer');
    }
    final content = (candidates.first as Map)['content'] as Map?;
    final parts = content?['parts'] as List? ?? const [];
    final text = parts
        .map((p) => (p as Map)['text'] as String? ?? '')
        .join()
        .trim();
    if (text.isEmpty) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Gemini returned an empty answer');
    }
    return text;
  }

  @override
  Future<List<String>> listModels() async {
    final resp = await guard(
        client.get(Uri.parse('$_base/models?pageSize=200&key=$apiKey')));
    if (resp.statusCode != 200) throw errorFor(resp.statusCode, resp.body);
    final models = (jsonDecode(resp.body) as Map)['models'] as List? ?? const [];
    return [
      for (final m in models)
        if (m is Map &&
            ((m['supportedGenerationMethods'] as List?) ?? const [])
                .contains('generateContent'))
          '${m['name']}'.replaceFirst('models/', ''),
    ];
  }

  /// Maps a Gemini error response to an [LlmException].
  static LlmException errorFor(int status, String body) {
    Map<String, dynamic>? error;
    try {
      error = (jsonDecode(body) as Map<String, dynamic>)['error']
          as Map<String, dynamic>?;
    } catch (_) {}
    final message = error?['message'] as String? ?? 'HTTP $status';
    final details = (error?['details'] as List?) ?? const [];
    final detailText = jsonEncode(details);

    Duration? retryAfter;
    for (final d in details) {
      final delay = d is Map ? d['retryDelay'] : null;
      final match = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch('$delay');
      if (match != null) {
        retryAfter = Duration(
            milliseconds: (double.parse(match.group(1)!) * 1000).ceil());
      }
    }

    if (status == 429) {
      final daily = detailText.contains('PerDay');
      return LlmException(
        daily ? LlmErrorKind.quotaExhausted : LlmErrorKind.rateLimited,
        daily ? 'Daily Gemini limit reached' : 'Gemini rate limit reached',
        retryAfter: retryAfter,
      );
    }
    if (status == 401 ||
        status == 403 ||
        detailText.contains('API_KEY_INVALID') ||
        message.contains('API key not valid')) {
      return const LlmException(
          LlmErrorKind.auth, 'Gemini rejected the API key');
    }
    if (status >= 500) {
      return LlmException(
        LlmErrorKind.other,
        'Gemini is having trouble ($status)',
        retryAfter: retryAfter ?? const Duration(seconds: 3),
      );
    }
    return LlmException(LlmErrorKind.other, 'Gemini error $status: $message');
  }
}
