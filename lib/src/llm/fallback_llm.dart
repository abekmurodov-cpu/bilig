import '../models/knowledge_item.dart';
import 'llm_provider.dart';

/// Uses [primary], switching to [backup] when the primary is rate-limited,
/// out of quota, rejecting its key, unreachable or failing. After such a
/// failure the primary rests (for as long as it asked, or a default) and
/// requests go straight to the backup, so a limited key isn't hammered.
///
/// A garbled reply ([LlmErrorKind.badResponse]) is not the service's fault and
/// doesn't switch. If the backup fails too, its error is what callers see.
class FallbackLlm implements LlmProvider {
  FallbackLlm(this.primary, this.backup, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final LlmProvider primary;
  final LlmProvider backup;
  final DateTime Function() _now;
  DateTime? _primaryRestsUntil;

  /// Whether requests currently go to the backup.
  bool get usingBackup {
    final until = _primaryRestsUntil;
    return until != null && _now().isBefore(until);
  }

  static Duration _restFor(LlmException e) => switch (e.kind) {
        LlmErrorKind.rateLimited => e.retryAfter ?? const Duration(minutes: 1),
        LlmErrorKind.quotaExhausted || LlmErrorKind.auth => const Duration(hours: 1),
        LlmErrorKind.network || LlmErrorKind.other => const Duration(minutes: 2),
        LlmErrorKind.badResponse => Duration.zero,
      };

  Future<T> _run<T>(Future<T> Function(LlmProvider llm) task) async {
    if (usingBackup) return task(backup);
    try {
      return await task(primary);
    } on LlmException catch (e) {
      if (e.kind == LlmErrorKind.badResponse) rethrow;
      _primaryRestsUntil = _now().add(_restFor(e));
      return task(backup);
    }
  }

  @override
  String get displayName => primary.displayName;

  @override
  Future<String> expandNote(KnowledgeItem item) =>
      _run((llm) => llm.expandNote(item));

  @override
  Future<McQuiz> generateQuiz(KnowledgeItem item, {int distractorCount = 3}) =>
      _run((llm) => llm.generateQuiz(item, distractorCount: distractorCount));

  @override
  Future<Map<String, List<McQuiz>>> generateQuizzes(
    List<KnowledgeItem> items, {
    int distractorCount = 3,
    int variantCount = 3,
  }) =>
      _run((llm) => llm.generateQuizzes(items,
          distractorCount: distractorCount, variantCount: variantCount));

  @override
  Future<LlmGrade> gradeAnswer(KnowledgeItem item, String answer) =>
      _run((llm) => llm.gradeAnswer(item, answer));

  @override
  Future<LlmGrade> gradeCode(KnowledgeItem item, String submitted) =>
      _run((llm) => llm.gradeCode(item, submitted));

  @override
  Future<String> suggestCategory(String front, String? back) =>
      _run((llm) => llm.suggestCategory(front, back));
}
