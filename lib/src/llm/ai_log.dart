import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../models/knowledge_item.dart';
import '../providers/settings_providers.dart';
import 'llm_provider.dart';

/// One request to an AI: which, for what, how long, and how it went.
class AiLogEntry {
  const AiLogEntry({
    required this.at,
    required this.ai,
    required this.task,
    required this.millis,
    this.error,
    this.kind,
  });

  final DateTime at;
  final String ai;
  final String task;
  final int millis;

  /// Null when it worked.
  final String? error;
  final LlmErrorKind? kind;

  bool get ok => error == null;

  Map<String, Object?> toMap() => {
        'at': at.toIso8601String(),
        'ai': ai,
        'task': task,
        'ms': millis,
        if (error != null) 'error': error,
        if (kind != null) 'kind': kind!.name,
      };

  static AiLogEntry? fromMap(Object? m) {
    if (m is! Map) return null;
    final at = DateTime.tryParse('${m['at']}');
    if (at == null) return null;
    return AiLogEntry(
      at: at,
      ai: '${m['ai'] ?? ''}',
      task: '${m['task'] ?? ''}',
      millis: (m['ms'] as num?)?.toInt() ?? 0,
      error: m['error'] as String?,
      kind: LlmErrorKind.values.where((k) => k.name == m['kind']).firstOrNull,
    );
  }
}

/// The last requests to the AIs, newest first, kept across restarts: when
/// something AI-made fails, this shows which AI was asked and what it said.
class AiLog extends Notifier<List<AiLogEntry>> {
  static const int keep = 60;

  @override
  List<AiLogEntry> build() {
    final raw = ref.read(settingsRepositoryProvider).getString(SettingsRepository.kAiLog);
    if (raw == null) return const [];
    try {
      return [for (final m in jsonDecode(raw) as List) ?AiLogEntry.fromMap(m)];
    } catch (_) {
      return const [];
    }
  }

  void add(AiLogEntry entry) {
    state = [entry, ...state.take(keep - 1)];
    ref.read(settingsRepositoryProvider).setString(
        SettingsRepository.kAiLog, jsonEncode([for (final e in state) e.toMap()]));
  }

  void clear() {
    state = const [];
    ref.read(settingsRepositoryProvider).setString(SettingsRepository.kAiLog, null);
  }
}

final aiLogProvider = NotifierProvider<AiLog, List<AiLogEntry>>(AiLog.new);

/// Wraps an AI so every request lands in the [AiLog].
class LoggedLlm implements LlmProvider {
  LoggedLlm(this.inner, this.record);

  final LlmProvider inner;
  final void Function(AiLogEntry) record;

  Future<T> _log<T>(String task, Future<T> Function() run) async {
    final watch = Stopwatch()..start();
    try {
      final result = await run();
      record(AiLogEntry(
          at: DateTime.now(), ai: inner.displayName, task: task, millis: watch.elapsedMilliseconds));
      return result;
    } catch (e) {
      record(AiLogEntry(
        at: DateTime.now(),
        ai: inner.displayName,
        task: task,
        millis: watch.elapsedMilliseconds,
        error: e is LlmException ? e.message : '$e',
        kind: e is LlmException ? e.kind : null,
      ));
      rethrow;
    }
  }

  @override
  String get displayName => inner.displayName;

  @override
  bool get canReadImages => inner.canReadImages;

  @override
  bool get canTranscribe => inner.canTranscribe;

  @override
  Future<String> expandNote(KnowledgeItem item) =>
      _log('expandNote', () => inner.expandNote(item));

  @override
  Future<McQuiz> generateQuiz(KnowledgeItem item, {int distractorCount = 3}) =>
      _log('generateQuiz', () => inner.generateQuiz(item, distractorCount: distractorCount));

  @override
  Future<Map<String, List<McQuiz>>> generateQuizzes(List<KnowledgeItem> items,
          {int distractorCount = 3, int variantCount = 3}) =>
      _log(
          'generateQuizzes',
          () => inner.generateQuizzes(items,
              distractorCount: distractorCount, variantCount: variantCount));

  @override
  Future<LlmGrade> gradeAnswer(KnowledgeItem item, String answer) =>
      _log('gradeAnswer', () => inner.gradeAnswer(item, answer));

  @override
  Future<LlmGrade> gradeCode(KnowledgeItem item, String submitted) =>
      _log('gradeCode', () => inner.gradeCode(item, submitted));

  @override
  Future<String> suggestCategory(String front, String? back) =>
      _log('suggestCategory', () => inner.suggestCategory(front, back));

  @override
  Future<String> explainMistake(KnowledgeItem item,
          {required String question, required String answer, String? studentAnswer}) =>
      _log(
          'explainMistake',
          () => inner.explainMistake(item,
              question: question, answer: answer, studentAnswer: studentAnswer));

  @override
  Future<List<NoteDraft>> notesFromImage(Attachment image) =>
      _log('notesFromImage', () => inner.notesFromImage(image));

  @override
  Future<List<NoteDraft>> notesFromText(String text) =>
      _log('notesFromText', () => inner.notesFromText(text));

  @override
  Future<String> transcribe(Attachment audio) =>
      _log('transcribe', () => inner.transcribe(audio));

  @override
  Future<List<String>> suggestHighlights(KnowledgeItem item) =>
      _log('suggestHighlights', () => inner.suggestHighlights(item));
}
