import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_llm.dart';
import 'llm_provider.dart';

/// [LlmProvider] for Claude via Anthropic's Messages API (raw HTTP — there is
/// no official Dart SDK).
class AnthropicProvider extends HttpLlm {
  AnthropicProvider({
    required this.apiKey,
    required this.model,
    super.client,
    super.sleep,
  });

  final String apiKey;
  final String model;

  static const _base = 'https://api.anthropic.com/v1';

  /// Room for the model's (always-on, on current models) thinking plus the
  /// short JSON answer.
  static const int maxTokens = 16000;

  @override
  String get displayName => 'Claude ($model)';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        // Required for calls straight from a browser (the web build).
        if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
      };

  /// Current-generation models accept `output_config.effort`; these short
  /// note/quiz tasks don't need deep reasoning, so ask for low effort there.
  bool get _supportsEffort =>
      RegExp(r'^claude-(opus|sonnet|haiku|fable)-5').hasMatch(model);

  @override
  Future<String> send(String prompt, {required bool json}) async {
    final resp = await guard(client.post(
      Uri.parse('$_base/messages'),
      headers: _headers,
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        if (_supportsEffort) 'output_config': {'effort': 'low'},
      }),
    ));
    if (resp.statusCode != 200) throw errorFor(resp);

    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Claude sent an unreadable reply');
    }
    if (data is! Map) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Claude sent an unreadable reply');
    }
    if (data['stop_reason'] == 'refusal') {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Claude declined this request');
    }
    // Only text blocks carry the answer; thinking blocks are skipped.
    final text = [
      for (final block in (data['content'] as List?) ?? const [])
        if (block is Map && block['type'] == 'text') '${block['text']}',
    ].join().trim();
    if (text.isEmpty) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'Claude returned an empty answer');
    }
    return text;
  }

  @override
  Future<List<String>> listModels() async {
    final resp = await guard(
        client.get(Uri.parse('$_base/models?limit=100'), headers: _headers));
    if (resp.statusCode != 200) throw errorFor(resp);
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final list = data is Map ? data['data'] as List? : null;
    return [
      for (final m in list ?? const [])
        if (m is Map && m['id'] != null) '${m['id']}',
    ];
  }

  /// Maps an Anthropic error response to an [LlmException].
  LlmException errorFor(http.Response resp) {
    final status = resp.statusCode;
    var type = '';
    var message = 'HTTP $status';
    try {
      final error = (jsonDecode(resp.body) as Map)['error'] as Map;
      type = '${error['type'] ?? ''}';
      message = '${error['message'] ?? message}';
    } catch (_) {}

    if (status == 401 || status == 403 ||
        type == 'authentication_error' || type == 'permission_error') {
      return const LlmException(
          LlmErrorKind.auth, 'Claude rejected the API key');
    }
    if (status == 402 ||
        type == 'billing_error' ||
        message.toLowerCase().contains('credit balance')) {
      return const LlmException(
          LlmErrorKind.quotaExhausted, 'Claude: no credit left on this key');
    }
    if (status == 429 || type == 'rate_limit_error') {
      return LlmException(
        LlmErrorKind.rateLimited,
        'Claude rate limit reached',
        retryAfter: HttpLlm.retryAfterHeader(resp),
      );
    }
    if (status >= 500) {
      // 529 = overloaded; 500 = transient service issue.
      return LlmException(
        LlmErrorKind.other,
        'Claude is having trouble ($status)',
        retryAfter: HttpLlm.retryAfterHeader(resp) ?? const Duration(seconds: 3),
      );
    }
    if (status == 404) {
      return LlmException(
          LlmErrorKind.other, 'Claude: model "$model" not found');
    }
    return LlmException(LlmErrorKind.other, 'Claude error $status: $message');
  }
}
