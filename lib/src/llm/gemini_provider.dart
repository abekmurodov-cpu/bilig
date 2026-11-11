import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'prompted_llm.dart';

/// [LlmProvider] backed by Google's Gemini REST API, using a user-supplied API
/// key (stored locally, never bundled). Calls the `generateContent` endpoint.
///
/// Short rate-limit hiccups and server overloads are retried after the delay
/// Gemini asks for; longer waits and daily-quota exhaustion surface as an
/// [LlmException] so the app can pause AI work instead of hammering the API.
class GeminiProvider extends PromptedLlm {
  GeminiProvider({
    required this.apiKey,
    this.model = 'gemini-2.5-flash',
    http.Client? client,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _sleep = sleep ?? Future.delayed;

  final String apiKey;
  final String model;
  final http.Client _client;
  final Future<void> Function(Duration) _sleep;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  /// Retries per call for transient errors.
  static const int maxRetries = 2;

  /// Waits longer than this aren't retried inline; the caller pauses instead.
  static const Duration maxInlineWait = Duration(seconds: 30);

  static const Duration requestTimeout = Duration(seconds: 60);

  @override
  String get displayName => 'Gemini ($model)';

  @override
  Future<String> complete(String prompt, {bool json = false}) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _send(prompt, json: json);
      } on LlmException catch (e) {
        final transient = e.kind == LlmErrorKind.rateLimited ||
            (e.kind == LlmErrorKind.other && e.retryAfter != null);
        final wait = e.retryAfter ?? Duration(seconds: 2 + 4 * attempt);
        if (!transient || attempt >= maxRetries || wait > maxInlineWait) {
          rethrow;
        }
        await _sleep(wait);
      }
    }
  }

  Future<String> _send(String prompt, {required bool json}) async {
    final uri = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');
    final generationConfig = <String, Object>{
      if (json) 'responseMimeType': 'application/json',
      // 2.5 Flash "thinks" by default, which costs tokens these short tasks
      // don't need.
      if (model.startsWith('gemini-2.5-flash'))
        'thinkingConfig': {'thinkingBudget': 0},
    };
    final http.Response resp;
    try {
      resp = await _client
          .post(
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
              if (generationConfig.isNotEmpty)
                'generationConfig': generationConfig,
            }),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const LlmException(
          LlmErrorKind.network, 'The AI took too long to answer');
    } on http.ClientException catch (e) {
      throw LlmException(LlmErrorKind.network, 'Network error: ${e.message}');
    }

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
        daily
            ? 'Daily Gemini limit reached'
            : 'Gemini rate limit reached',
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
