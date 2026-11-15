import 'dart:async';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'prompted_llm.dart';

/// A [PromptedLlm] reached over HTTP. Owns what every backend shares: request
/// timeouts, network-error mapping, and retrying short rate limits / server
/// overloads after the delay the service asks for. Longer waits surface as an
/// [LlmException] so the app pauses AI work instead of hammering the API.
abstract class HttpLlm extends PromptedLlm {
  HttpLlm({http.Client? client, Future<void> Function(Duration)? sleep})
      : client = client ?? http.Client(),
        _sleep = sleep ?? Future.delayed;

  final http.Client client;
  final Future<void> Function(Duration) _sleep;

  /// Retries per call for transient errors.
  static const int maxRetries = 2;

  /// Waits longer than this aren't retried inline; the caller pauses instead.
  static const Duration maxInlineWait = Duration(seconds: 30);

  static const Duration requestTimeout = Duration(seconds: 60);

  /// Sends one prompt (with any [attachments]), without retrying.
  Future<String> send(String prompt,
      {required bool json, List<Attachment> attachments = const []});

  /// Model ids the key can use, as reported by the service.
  Future<List<String>> listModels();

  @override
  Future<String> complete(String prompt,
      {bool json = false, List<Attachment> attachments = const []}) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await send(prompt, json: json, attachments: attachments);
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

  /// One tiny request that proves the key, model and connection all work.
  Future<void> testConnection() async {
    await complete('Reply with the single word OK.');
  }

  /// [request] with a timeout, mapping connection failures to
  /// [LlmErrorKind.network].
  Future<http.Response> guard(Future<http.Response> request) async {
    try {
      return await request.timeout(requestTimeout);
    } on TimeoutException {
      throw const LlmException(
          LlmErrorKind.network, 'The AI took too long to answer');
    } on http.ClientException catch (e) {
      throw LlmException(LlmErrorKind.network, 'Network error: ${e.message}');
    }
  }

  /// The `Retry-After` header in seconds, if present.
  static Duration? retryAfterHeader(http.Response resp) {
    final value = double.tryParse(resp.headers['retry-after'] ?? '');
    return value == null ? null : Duration(milliseconds: (value * 1000).ceil());
  }
}
