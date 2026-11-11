import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_llm.dart';
import 'llm_provider.dart';

/// [LlmProvider] for any service speaking the OpenAI Chat Completions format:
/// OpenAI itself, DeepSeek, Groq, OpenRouter, Mistral, xAI, and local servers
/// such as Ollama or LM Studio. Only [baseUrl] (ending in `/v1`) and the key
/// differ between them.
class OpenAiCompatibleProvider extends HttpLlm {
  OpenAiCompatibleProvider({
    required this.serviceName,
    required String baseUrl,
    required this.apiKey,
    required this.model,
    this.extraHeaders = const {},
    super.client,
    super.sleep,
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  /// Shown in error messages ("DeepSeek rejected the API key").
  final String serviceName;
  final String baseUrl;

  /// May be empty for local servers that need no key.
  final String apiKey;
  final String model;
  final Map<String, String> extraHeaders;

  /// Turned off for the rest of the session when the model rejects
  /// `response_format` (some OpenRouter and local models do).
  bool _jsonMode = true;

  @override
  String get displayName => '$serviceName ($model)';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        ...extraHeaders,
      };

  @override
  Future<String> send(String prompt, {required bool json}) async {
    final useJsonMode = json && _jsonMode;
    final resp = await guard(client.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: _headers,
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        if (useJsonMode) 'response_format': {'type': 'json_object'},
      }),
    ));
    if (resp.statusCode == 400 &&
        useJsonMode &&
        resp.body.contains('response_format')) {
      _jsonMode = false;
      return send(prompt, json: json);
    }
    if (resp.statusCode != 200) throw errorFor(resp);

    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      throw LlmException(
          LlmErrorKind.badResponse, '$serviceName sent an unreadable reply');
    }
    final choices = data is Map ? data['choices'] as List? : null;
    final message =
        (choices == null || choices.isEmpty) ? null : (choices.first as Map)['message'];
    final text = (message is Map ? message['content'] as String? : null)?.trim();
    if (text == null || text.isEmpty) {
      throw LlmException(
          LlmErrorKind.badResponse, '$serviceName returned an empty answer');
    }
    return text;
  }

  @override
  Future<List<String>> listModels() async {
    final resp =
        await guard(client.get(Uri.parse('$baseUrl/models'), headers: _headers));
    if (resp.statusCode != 200) throw errorFor(resp);
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final list = data is Map ? data['data'] as List? : null;
    return [
      for (final m in list ?? const [])
        if (m is Map && m['id'] != null) '${m['id']}',
    ];
  }

  /// Maps an OpenAI-style error response to an [LlmException].
  LlmException errorFor(http.Response resp) {
    final status = resp.statusCode;
    String message = 'HTTP $status';
    String code = '';
    try {
      final error = (jsonDecode(resp.body) as Map)['error'];
      if (error is Map) {
        message = '${error['message'] ?? message}';
        code = '${error['code'] ?? ''} ${error['type'] ?? ''}';
      } else if (error is String) {
        message = error;
      }
    } catch (_) {}
    final lower = '$message $code'.toLowerCase();

    if (status == 401 || status == 403) {
      return LlmException(
          LlmErrorKind.auth, '$serviceName rejected the API key');
    }
    if (status == 402 ||
        lower.contains('insufficient_quota') ||
        lower.contains('insufficient balance') ||
        lower.contains('credit')) {
      return LlmException(LlmErrorKind.quotaExhausted,
          '$serviceName: no credit or quota left');
    }
    if (status == 429) {
      return LlmException(
        LlmErrorKind.rateLimited,
        '$serviceName rate limit reached',
        retryAfter: HttpLlm.retryAfterHeader(resp),
      );
    }
    if (status >= 500) {
      return LlmException(
        LlmErrorKind.other,
        '$serviceName is having trouble ($status)',
        retryAfter: HttpLlm.retryAfterHeader(resp) ?? const Duration(seconds: 3),
      );
    }
    if (status == 404) {
      return LlmException(
          LlmErrorKind.other, '$serviceName: model "$model" not found');
    }
    return LlmException(LlmErrorKind.other, '$serviceName error $status: $message');
  }
}
