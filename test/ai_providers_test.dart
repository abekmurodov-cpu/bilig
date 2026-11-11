import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knowledge/src/data/secret_store.dart';
import 'package:knowledge/src/data/settings_repository.dart';
import 'package:knowledge/src/llm/ai_services.dart';
import 'package:knowledge/src/llm/anthropic_provider.dart';
import 'package:knowledge/src/llm/http_llm.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/llm/llm_providers.dart';
import 'package:knowledge/src/llm/openai_compatible_provider.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/providers/settings_providers.dart';
import 'package:knowledge/src/sync/sync_providers.dart';

Matcher llmError(LlmErrorKind kind) =>
    throwsA(isA<LlmException>().having((e) => e.kind, 'kind', kind));

http.Response jsonResponse(Object body, int status, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?headers});

void main() {
  group('guessService', () {
    test('recognizes key prefixes', () {
      expect(guessService('AIzaSyXXXX').service, AiService.gemini);
      expect(guessService(' sk-ant-api03-xyz ').service, AiService.claude);
      expect(guessService('sk-or-v1-abc').service, AiService.openrouter);
      expect(guessService('gsk_abc').service, AiService.groq);
      expect(guessService('xai-abc').service, AiService.xai);
      expect(guessService('sk-proj-abc').service, AiService.openai);
    });

    test('a plain sk- key is ambiguous, an unknown one is empty', () {
      expect(guessService('sk-abc123').candidates,
          [AiService.openai, AiService.deepseek]);
      expect(guessService('sk-abc123').service, isNull);
      expect(guessService('8f3a9c').candidates, isEmpty);
    });
  });

  group('recommendedModel', () {
    test('OpenAI: newest stable mini chat model, skipping non-chat ids', () {
      expect(
        recommendedModel(AiService.openai, [
          'gpt-4o-mini',
          'gpt-5-mini',
          'gpt-5-mini-2025-08-07',
          'gpt-4.1-mini',
          'text-embedding-3-small',
          'gpt-realtime-mini',
          'gpt-5',
        ]),
        'gpt-5-mini',
      );
    });

    test('services with a default use it when available', () {
      expect(recommendedModel(AiService.claude, ['claude-haiku-5-5', 'claude-opus-5-5']),
          'claude-haiku-5-5');
      expect(recommendedModel(AiService.deepseek, const []), 'deepseek-chat');
    });

    test('OpenRouter prefers a free model', () {
      expect(
        recommendedModel(AiService.openrouter, [
          'openai/gpt-5',
          'meta-llama/llama-3.3-70b-instruct:free',
          'anthropic/claude-opus-5-5',
        ]),
        'meta-llama/llama-3.3-70b-instruct:free',
      );
    });

    test('Gemini prefers stable flash-lite over previews', () {
      expect(
        recommendedModel(AiService.gemini, [
          'gemini-2.5-flash',
          'gemini-2.5-flash-lite',
          'gemini-9-flash-lite-preview',
          'text-embedding-004',
        ]),
        'gemini-2.5-flash-lite',
      );
    });

    test('custom servers fall back to the first chat model', () {
      expect(recommendedModel(AiService.custom, ['nomic-embed-text', 'llama3.2']),
          'llama3.2');
      expect(recommendedModel(AiService.custom, const []), isNull);
    });
  });

  group('OpenAiCompatibleProvider', () {
    OpenAiCompatibleProvider make(MockClient client) => OpenAiCompatibleProvider(
          serviceName: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/v1/',
          apiKey: 'sk-test',
          model: 'deepseek-chat',
          client: client,
          sleep: (_) async {},
        );

    test('sends a chat completion with JSON mode and reads the reply', () async {
      late http.Request sent;
      final llm = make(MockClient((req) async {
        sent = req;
        return jsonResponse({
          'choices': [
            {'message': {'role': 'assistant', 'content': '{"correct": true, "feedback": "Yes"}'}},
          ],
        }, 200);
      }));
      final grade = await llm.gradeAnswer(
          _note('What is 2+2?', '4'), 'four');
      expect(grade.correct, isTrue);
      expect(sent.url.toString(), 'https://api.deepseek.com/v1/chat/completions');
      expect(sent.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(sent.body) as Map;
      expect(body['model'], 'deepseek-chat');
      expect(body['response_format'], {'type': 'json_object'});
    });

    test('drops JSON mode once when the model rejects it', () async {
      final bodies = <Map>[];
      final llm = make(MockClient((req) async {
        final body = jsonDecode(req.body) as Map;
        bodies.add(body);
        if (body.containsKey('response_format')) {
          return jsonResponse({
            'error': {'message': 'response_format is not supported by this model'},
          }, 400);
        }
        return jsonResponse({
          'choices': [
            {'message': {'content': '{"correct": false}'}},
          ],
        }, 200);
      }));
      await llm.gradeAnswer(_note('q', 'a'), 'b');
      await llm.gradeAnswer(_note('q', 'a'), 'b');
      expect(bodies.map((b) => b.containsKey('response_format')),
          [true, false, false]);
    });

    test('maps errors', () async {
      Future<void> expectKind(http.Response resp, LlmErrorKind kind) =>
          expectLater(make(MockClient((_) async => resp)).suggestCategory('x', null),
              llmError(kind));
      await expectKind(jsonResponse({'error': {'message': 'bad key'}}, 401), LlmErrorKind.auth);
      await expectKind(
          jsonResponse({'error': {'message': 'Insufficient Balance'}}, 402),
          LlmErrorKind.quotaExhausted);
      await expectKind(
          jsonResponse({'error': {'message': 'quota', 'code': 'insufficient_quota'}}, 429),
          LlmErrorKind.quotaExhausted);
      await expectKind(
          jsonResponse({'error': {'message': 'slow down'}}, 429, headers: {'retry-after': '120'}),
          LlmErrorKind.rateLimited);
      await expectKind(
          jsonResponse({'error': {'message': 'The model does not exist'}}, 404),
          LlmErrorKind.other);
    });

    test('retries a short Retry-After', () async {
      var calls = 0;
      final llm = make(MockClient((_) async {
        calls++;
        if (calls == 1) {
          return jsonResponse({'error': {'message': 'busy'}}, 429, headers: {'retry-after': '2'});
        }
        return jsonResponse({
          'choices': [
            {'message': {'content': 'Math'}},
          ],
        }, 200);
      }));
      expect(await llm.suggestCategory('x', null), 'Math');
      expect(calls, 2);
    });

    test('lists models and omits auth for keyless local servers', () async {
      late http.Request sent;
      final llm = OpenAiCompatibleProvider(
        serviceName: 'AI server',
        baseUrl: 'http://localhost:11434/v1',
        apiKey: '',
        model: 'llama3.2',
        client: MockClient((req) async {
          sent = req;
          return jsonResponse({
            'data': [
              {'id': 'llama3.2'},
              {'id': 'qwen3'},
            ],
          }, 200);
        }),
      );
      expect(await llm.listModels(), ['llama3.2', 'qwen3']);
      expect(sent.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('AnthropicProvider', () {
    test('sends Messages API headers, low effort, and reads only text blocks', () async {
      late http.Request sent;
      final llm = AnthropicProvider(
        apiKey: 'sk-ant-test',
        model: 'claude-opus-5-5',
        client: MockClient((req) async {
          sent = req;
          return jsonResponse({
            'content': [
              {'type': 'thinking', 'thinking': ''},
              {'type': 'text', 'text': 'Biology'},
            ],
            'stop_reason': 'end_turn',
          }, 200);
        }),
      );
      expect(await llm.suggestCategory('mitochondria', null), 'Biology');
      expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['x-api-key'], 'sk-ant-test');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(sent.body) as Map;
      expect(body['output_config'], {'effort': 'low'});
      expect(body.containsKey('thinking'), isFalse);
    });

    test('older models get no effort setting', () async {
      late Map body;
      final llm = AnthropicProvider(
        apiKey: 'k',
        model: 'claude-haiku-4-5',
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map;
          return jsonResponse({
            'content': [
              {'type': 'text', 'text': 'X'},
            ],
          }, 200);
        }),
      );
      await llm.suggestCategory('x', null);
      expect(body.containsKey('output_config'), isFalse);
    });

    test('maps errors and refusals', () async {
      Future<void> expectKind(http.Response resp, LlmErrorKind kind) => expectLater(
            AnthropicProvider(
              apiKey: 'k',
              model: 'claude-opus-5-5',
              client: MockClient((_) async => resp),
              sleep: (_) async {},
            ).suggestCategory('x', null),
            llmError(kind),
          );
      Map err(String type, String message) =>
          {'type': 'error', 'error': {'type': type, 'message': message}};
      await expectKind(jsonResponse(err('authentication_error', 'invalid x-api-key'), 401),
          LlmErrorKind.auth);
      await expectKind(
          jsonResponse(err('invalid_request_error',
              'Your credit balance is too low to access the Anthropic API.'), 400),
          LlmErrorKind.quotaExhausted);
      await expectKind(jsonResponse(err('rate_limit_error', 'slow'), 429, headers: {'retry-after': '90'}),
          LlmErrorKind.rateLimited);
      await expectKind(jsonResponse(err('overloaded_error', 'Overloaded'), 529),
          LlmErrorKind.other);
      await expectKind(
          jsonResponse({'content': [], 'stop_reason': 'refusal'}, 200),
          LlmErrorKind.badResponse);
    });

    test('overload is retried', () async {
      var calls = 0;
      final llm = AnthropicProvider(
        apiKey: 'k',
        model: 'claude-opus-5-5',
        sleep: (_) async {},
        client: MockClient((_) async {
          calls++;
          return jsonResponse(
              {'type': 'error', 'error': {'type': 'overloaded_error', 'message': 'Overloaded'}}, 529);
        }),
      );
      await expectLater(llm.suggestCategory('x', null), throwsA(isA<LlmException>()));
      expect(calls, HttpLlm.maxRetries + 1);
    });
  });

  group('AiConfigNotifier', () {
    late SettingsRepository settings;
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync().path);
      settings = await SettingsRepository.open();
    });
    setUp(() async {
      for (final k in [
        SettingsRepository.kGeminiApiKey,
        SettingsRepository.kGeminiModel,
        SettingsRepository.kAiService,
        SettingsRepository.kAiModel,
        SettingsRepository.kAiBaseUrl,
        SettingsRepository.kAiModels,
        SettingsRepository.kTelegramBotToken,
        SettingsRepository.kTelegramChatId,
      ]) {
        await settings.setString(k, null);
      }
    });

    ProviderContainer containerWith(SecretStore secrets) => ProviderContainer(overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          secretStoreProvider.overrideWithValue(secrets),
        ]);

    test('migrates a legacy Gemini key into the secret store', () async {
      await settings.setString(SettingsRepository.kGeminiApiKey, 'AIzaOld');
      await settings.setString(SettingsRepository.kGeminiModel, 'gemini-2.5-flash');
      final secrets = SecretStore.memory();
      final c = containerWith(secrets);
      addTearDown(c.dispose);

      final config = c.read(aiConfigProvider)!;
      expect(config.service, AiService.gemini);
      expect(config.model, 'gemini-2.5-flash');
      expect(config.apiKey, 'AIzaOld');
      // The disk writes run in the background; wait for them.
      for (var i = 0;
          i < 100 && settings.getString(SettingsRepository.kGeminiApiKey) != null;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(secrets.read(SecretStore.kAiApiKey), 'AIzaOld');
      expect(settings.getString(SettingsRepository.kGeminiApiKey), isNull);
      expect(settings.getString(SettingsRepository.kAiService), 'gemini');

      // A fresh start reads the migrated settings.
      final again = containerWith(secrets);
      addTearDown(again.dispose);
      expect(again.read(aiConfigProvider)!.model, 'gemini-2.5-flash');
    });

    test('moves a plain-text Telegram token into the secret store', () async {
      await settings.setString(SettingsRepository.kTelegramBotToken, '123:abc');
      await settings.setString(SettingsRepository.kTelegramChatId, '-10042');
      final secrets = SecretStore.memory();
      final c = containerWith(secrets);
      addTearDown(c.dispose);

      expect(c.read(telegramConfigProvider)!.botToken, '123:abc');
      for (var i = 0;
          i < 100 && settings.getString(SettingsRepository.kTelegramBotToken) != null;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(settings.getString(SettingsRepository.kTelegramBotToken), isNull);
      expect(secrets.read(SecretStore.kTelegramBotToken), '123:abc');
      await c.read(telegramConfigProvider.notifier).detach();
      expect(secrets.read(SecretStore.kTelegramBotToken), isNull);
    });

    test('attach, change model, detach', () async {
      final secrets = SecretStore.memory();
      final c = containerWith(secrets);
      addTearDown(c.dispose);
      expect(c.read(llmProvider), isNull);

      await c.read(aiConfigProvider.notifier).attach(
            const AiConfig(service: AiService.groq, model: 'llama-x', apiKey: 'gsk_1'),
            models: ['llama-x', 'whisper-large-v3', 'gpt-oss-120b'],
          );
      expect(c.read(llmProvider)!.displayName, 'Groq (llama-x)');
      expect(c.read(aiConfigProvider.notifier).models, ['gpt-oss-120b', 'llama-x']);
      expect(settings.getString(SecretStore.kAiApiKey), isNull,
          reason: 'the key is not kept in plain settings');

      await c.read(aiConfigProvider.notifier).setModel('gpt-oss-120b');
      expect(c.read(aiConfigProvider)!.model, 'gpt-oss-120b');

      await c.read(aiConfigProvider.notifier).detach();
      expect(c.read(aiConfigProvider), isNull);
      expect(secrets.read(SecretStore.kAiApiKey), isNull);
    });
  });
}

KnowledgeItem _note(String front, String back) {
  final now = DateTime(2026, 1, 1);
  return KnowledgeItem(
    id: 'n',
    front: front,
    back: back,
    type: KnowledgeType.question,
    createdAt: now,
    dueDate: now,
  );
}
