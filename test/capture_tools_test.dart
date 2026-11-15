import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knowledge/src/capture/split_notes.dart';
import 'package:knowledge/src/llm/anthropic_provider.dart';
import 'package:knowledge/src/llm/fallback_llm.dart';
import 'package:knowledge/src/llm/gemini_provider.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/llm/openai_compatible_provider.dart';
import 'package:knowledge/src/llm/prompted_llm.dart';
import 'package:knowledge/src/models/knowledge_item.dart';

import 'quiz_prep_test.dart' show FakeLlm;

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
const _notesReply = '{"notes": [{"front": "Mitochondria", "back": "Makes ATP.", '
    '"type": "concept", "category": "Biology"}, {"front": "mitochondria"}, '
    '{"front": ""}, {"front": "What is 2+2?", "back": "4", "type": "nonsense"}]}';

void main() {
  group('splitting pasted text without AI', () {
    test('cues and answers from common line shapes', () {
      final drafts = splitLocally('''
- Mitochondria — makes ATP for the cell
2. Osmosis: water moving across a membrane
What is the capital of France? Paris
Q: Who wrote Hamlet?
A: Shakespeare
Just a loose fact without an answer.
Ratio = part / whole
''');
      expect([for (final d in drafts) '${d.front} | ${d.back}'], [
        'Mitochondria | makes ATP for the cell',
        'Osmosis | water moving across a membrane',
        'What is the capital of France? | Paris',
        'Who wrote Hamlet? | Shakespeare',
        'Just a loose fact without an answer. | null',
        'Ratio | part / whole',
      ]);
      expect(drafts[0].type, KnowledgeType.concept);
      expect(drafts[2].type, KnowledgeType.question);
      expect(drafts[4].type, KnowledgeType.fact);
    });

    test('a long sentence with a colon stays one note', () {
      final drafts = splitLocally(
          'In the year 1492 the explorer sailed west across the ocean: a long trip');
      expect(drafts.single.back, isNull);
    });
  });

  test('proposed notes drop empty and repeated ones; unknown types become concepts',
      () {
    final drafts = PromptedLlm.parseDrafts(_notesReply);
    expect(drafts.map((d) => d.front), ['Mitochondria', 'What is 2+2?']);
    expect(drafts.first.category, 'Biology');
    expect(drafts.last.type, KnowledgeType.concept);
    expect(() => PromptedLlm.parseDrafts('nope'), throwsA(isA<LlmException>()));
  });

  test('image type is read from the bytes', () {
    expect(Attachment.image(_png).mimeType, 'image/png');
    expect(Attachment.image(Uint8List.fromList([0xFF, 0xD8, 0xFF])).mimeType,
        'image/jpeg');
  });

  group('photos and voice reach each service in its own format', () {
    test('Gemini: inline data before the prompt', () async {
      late Map body;
      final llm = GeminiProvider(
        apiKey: 'k',
        client: MockClient((r) async {
          body = jsonDecode(r.body) as Map;
          return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': _notesReply},
                      ],
                    },
                  },
                ],
              }),
              200);
        }),
      );
      final drafts = await llm.notesFromImage(Attachment.image(_png));
      expect(drafts, hasLength(2));
      final parts = (body['contents'] as List).single['parts'] as List;
      expect(parts.first['inline_data']['mime_type'], 'image/png');
      expect(parts.first['inline_data']['data'], base64Encode(_png));
      expect(llm.canTranscribe, isTrue);
    });

    test('OpenAI format: image_url data URL; transcription endpoint for audio',
        () async {
      final seen = <http.BaseRequest>[];
      String? chatBody;
      final llm = OpenAiCompatibleProvider(
        serviceName: 'Groq',
        baseUrl: 'https://api.groq.com/openai/v1',
        apiKey: 'gsk',
        model: 'llama',
        transcribeModel: 'whisper-large-v3-turbo',
        client: MockClient((r) async {
          seen.add(r);
          if (r.url.path.endsWith('/audio/transcriptions')) {
            expect(r.headers['content-type'], startsWith('multipart/form-data'));
            expect(r.body, contains('whisper-large-v3-turbo'));
            return http.Response('{"text": " salom dunyo "}', 200);
          }
          chatBody = r.body;
          return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': _notesReply},
                  },
                ],
              }),
              200);
        }),
      );
      await llm.notesFromImage(Attachment.image(_png));
      final content = (jsonDecode(chatBody!)['messages'] as List).single['content'] as List;
      expect(content.last['image_url']['url'],
          'data:image/png;base64,${base64Encode(_png)}');
      expect(
          await llm.transcribe(Attachment('audio/wav', Uint8List(4))), 'salom dunyo');
      expect(seen.last.headers['Authorization'], 'Bearer gsk');
    });

    test('DeepSeek has no vision and no transcription', () {
      final llm = OpenAiCompatibleProvider(
          serviceName: 'DeepSeek', baseUrl: 'x', apiKey: 'k', model: 'm', vision: false);
      expect(llm.canReadImages, isFalse);
      expect(llm.canTranscribe, isFalse);
    });

    test('Claude: base64 image block', () async {
      late Map body;
      final llm = AnthropicProvider(
        apiKey: 'k',
        model: 'claude-haiku-5-5',
        client: MockClient((r) async {
          body = jsonDecode(r.body) as Map;
          return http.Response(
              jsonEncode({
                'content': [
                  {'type': 'text', 'text': _notesReply},
                ],
                'stop_reason': 'end_turn',
              }),
              200);
        }),
      );
      await llm.notesFromImage(Attachment.image(_png));
      final content = (body['messages'] as List).single['content'] as List;
      expect(content.first['source']['media_type'], 'image/png');
      expect(content.last['type'], 'text');
    });
  });

  test('a backup that can read photos is used when the main AI can’t', () async {
    final primary = _Drafting(canSee: false, name: 'main');
    final backup = _Drafting(canSee: true, name: 'backup');
    final llm = FallbackLlm(primary, backup);
    expect(llm.canReadImages, isTrue);
    final drafts = await llm.notesFromImage(Attachment.image(_png));
    expect(drafts.single.front, 'from backup');
    expect(llm.canTranscribe, isFalse);
  });
}

class _Drafting extends FakeLlm {
  _Drafting({required this.canSee, required this.name});
  final bool canSee;
  final String name;

  @override
  bool get canReadImages => canSee;

  @override
  Future<List<NoteDraft>> notesFromImage(Attachment image) async =>
      [NoteDraft(front: 'from $name')];
}
