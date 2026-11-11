import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knowledge/src/llm/gemini_provider.dart';
import 'package:knowledge/src/llm/http_llm.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/llm/prompted_llm.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/practice/answer_matching.dart';
import 'package:knowledge/src/practice/quiz_quality.dart';

KnowledgeItem note(String id, String front, {String? back}) {
  final now = DateTime(2026, 1, 1);
  return KnowledgeItem(
    id: id,
    front: front,
    back: back,
    type: KnowledgeType.fact,
    createdAt: now,
    dueDate: now,
  );
}

String geminiReply(String text) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        },
      ],
    });

String geminiError(int code, String status, List<Object> details) => jsonEncode({
      'error': {'code': code, 'message': status, 'status': status, 'details': details},
    });

void main() {
  final notes = [
    note('uuid-a', 'Water boils at 100°C'),
    note('uuid-b', 'git reset --hard', back: 'Discards local changes'),
  ];

  group('batch prompt + parsing', () {
    test('numbers notes and includes details', () {
      final prompt = PromptedLlm.quizBatchPrompt(notes, 3);
      expect(prompt, contains('[1] (fact) Water boils at 100°C'));
      expect(prompt, contains('[2] (fact) git reset --hard'));
      expect(prompt, contains('Detail: Discards local changes'));
      expect(prompt, isNot(contains('uuid-a')));
    });

    test('maps numbered items back to note ids, dropping broken ones', () {
      const raw = '```json\n{"items": ['
          '{"id": "2", "question": "Which command discards changes?", '
          '"answer": "git reset --hard", "distractors": ["git stash", "git add", "git log"]},'
          '{"id": 1, "question": "", "answer": "x", "distractors": []},'
          '{"id": 9, "question": "q", "answer": "a", "distractors": ["b"]}'
          ']}\n```';
      final quizzes = PromptedLlm.parseQuizBatch(raw, notes);
      expect(quizzes.keys, ['uuid-b']);
      expect(quizzes['uuid-b']!.distractors, hasLength(3));
    });

    test('accepts a bare list', () {
      const raw = '[{"id": 1, "question": "At what temperature does water boil?", '
          '"answer": "100°C", "distractors": ["90°C", "80°C"]}]';
      expect(PromptedLlm.parseQuizBatch(raw, notes).keys, ['uuid-a']);
    });

    test('garbage is a badResponse', () {
      expect(
        () => PromptedLlm.parseQuizBatch('sorry, I cannot', notes),
        throwsA(isA<LlmException>()
            .having((e) => e.kind, 'kind', LlmErrorKind.badResponse)),
      );
    });
  });

  group('GeminiProvider', () {
    test('asks for strict JSON and batches all notes in one request', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(
          geminiReply('{"items": ['
              '{"id": 1, "question": "At what temperature does water boil?", '
              '"answer": "100°C", "distractors": ["90°C", "80°C", "120°C"]},'
              '{"id": 2, "question": "Which git command discards local changes?", '
              '"answer": "git reset --hard", "distractors": ["git stash", "git add .", "git log"]}'
              ']}'),
          200,
        );
      });
      final llm = GeminiProvider(apiKey: 'k', model: 'gemini-x', client: client);
      final quizzes = await llm.generateQuizzes(notes);
      expect(bodies, hasLength(1));
      expect(bodies.single['generationConfig']['responseMimeType'],
          'application/json');
      expect(quizzes.keys, containsAll(['uuid-a', 'uuid-b']));
    });

    test('waits out a short rate limit and retries', () async {
      final waits = <Duration>[];
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            geminiError(429, 'RESOURCE_EXHAUSTED', [
              {'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '7s'},
            ]),
            429,
          );
        }
        return http.Response(geminiReply('Tech'), 200);
      });
      final llm = GeminiProvider(
        apiKey: 'k',
        client: client,
        sleep: (d) async => waits.add(d),
      );
      expect(await llm.suggestCategory('front', null), 'Tech');
      expect(waits, [const Duration(seconds: 7)]);
    });

    test('a long wait is not retried inline', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(
          geminiError(429, 'RESOURCE_EXHAUSTED', [
            {'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '50s'},
          ]),
          429,
        );
      });
      final llm = GeminiProvider(apiKey: 'k', client: client, sleep: (_) async {});
      await expectLater(
        llm.suggestCategory('front', null),
        throwsA(isA<LlmException>()
            .having((e) => e.kind, 'kind', LlmErrorKind.rateLimited)
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 50))),
      );
      expect(calls, 1);
    });

    test('a used-up daily quota is reported, not retried', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(
          geminiError(429, 'RESOURCE_EXHAUSTED', [
            {
              '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
              'violations': [
                {'quotaId': 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'},
              ],
            },
            {'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '3s'},
          ]),
          429,
        );
      });
      final llm = GeminiProvider(apiKey: 'k', client: client, sleep: (_) async {});
      await expectLater(
        llm.suggestCategory('front', null),
        throwsA(isA<LlmException>()
            .having((e) => e.kind, 'kind', LlmErrorKind.quotaExhausted)),
      );
      expect(calls, 1);
    });

    test('an invalid key is an auth error', () async {
      final client = MockClient((req) async => http.Response(
            geminiError(400, 'INVALID_ARGUMENT', [
              {'@type': 'type.googleapis.com/google.rpc.ErrorInfo', 'reason': 'API_KEY_INVALID'},
            ]),
            400,
          ));
      final llm = GeminiProvider(apiKey: 'k', client: client);
      await expectLater(
        llm.suggestCategory('front', null),
        throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.auth)),
      );
    });

    test('server overload is retried a bounded number of times', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response('overloaded', 503);
      });
      final llm = GeminiProvider(apiKey: 'k', client: client, sleep: (_) async {});
      await expectLater(llm.suggestCategory('front', null), throwsA(isA<LlmException>()));
      expect(calls, HttpLlm.maxRetries + 1);
    });
  });

  group('quizProblem', () {
    McQuiz quiz(String q, String a, List<String> d) =>
        McQuiz(question: q, answer: a, distractors: d);

    test('accepts a well-formed quiz', () {
      expect(
        quizProblem(quiz('At what temperature does water boil?', '100°C',
            ['90°C', '80°C', '120°C'])),
        isNull,
      );
    });

    test('rejects too few or repeated options', () {
      expect(quizProblem(quiz('Q?', 'Paris', ['Lyon'])), QuizProblem.tooFewOptions);
      expect(quizProblem(quiz('Q?', 'Paris', ['paris.', 'Lyon'])),
          QuizProblem.duplicateOptions);
    });

    test('rejects an answer leaked into the question', () {
      expect(
        quizProblem(quiz('Which command, git reset --hard, discards changes?',
            'git reset --hard', ['git stash', 'git add', 'git log'])),
        QuizProblem.answerInQuestion,
      );
    });

    test('rejects a correct option that stands out by length', () {
      expect(
        quizProblem(quiz(
          'What does a mutex do?',
          'It ensures only one thread at a time can enter a critical section of code',
          ['Sorts data', 'Frees memory', 'Opens files'],
        )),
        QuizProblem.lengthGivesAway,
      );
    });
  });

  group('isConfidentlyCorrect', () {
    test('accepts exact, typo and containing answers', () {
      expect(isConfidentlyCorrect('Mitochondria', 'mitochondria'), isTrue);
      expect(isConfidentlyCorrect('mitocondria', 'mitochondria'), isTrue);
      expect(isConfidentlyCorrect('it is the mitochondria', 'mitochondria'), isTrue);
    });

    test('rejects a fragment of the answer', () {
      expect(isConfidentlyCorrect('the', 'the mitochondria'), isFalse);
      expect(isConfidentlyCorrect('ribosome', 'mitochondria'), isFalse);
    });
  });
}
