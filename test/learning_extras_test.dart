import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/notifications/notification_providers.dart';
import 'package:knowledge/src/practice/practice_models.dart';

KnowledgeItem note(String id, DateTime due, {String? back}) => KnowledgeItem(
    id: id,
    front: 'Q$id',
    back: back,
    type: KnowledgeType.fact,
    createdAt: DateTime(2026, 11, 1),
    dueDate: due);

void main() {
  test('reminders say how many cards wait, and skip days with none', () {
    final now = DateTime(2026, 11, 16, 10); // after today's 9:00 reminder
    final notes = [
      note('a', DateTime(2026, 11, 16, 8)), // due now
      note('b', DateTime(2026, 11, 17, 7)), // due before tomorrow 9:00
      note('c', DateTime(2026, 11, 20, 12)), // due after the 20th's 9:00
    ];
    final plan = reminderPlan(notes, 9, 0, const AppStrings(AppLanguage.en), now: now);
    expect(plan.keys.first, DateTime(2026, 11, 17, 9));
    expect(plan[DateTime(2026, 11, 17, 9)], '2 cards waiting · about 1 min');
    expect(plan[DateTime(2026, 11, 21, 9)], '3 cards waiting · about 1 min');
    expect(plan.keys.every((d) => d.isAfter(now)), isTrue);
    expect(reminderPlan(const [], 9, 0, const AppStrings(AppLanguage.en), now: now), isEmpty);
  });

  test('reversed practice needs notes with an answer', () {
    final due = DateTime(2026, 11, 16);
    final all = [note('a', due, back: 'Tokyo'), note('b', due)];
    const reversed = PracticeConfig(
        method: PracticeMethod.flashcard, scope: PracticeScope.all, reverse: true);
    expect(reversed.buildQueue(all: all, due: all).map((n) => n.id), ['a']);
    expect(PracticeConfig.canReverse(PracticeMethod.multipleChoice), isFalse);
  });
}
