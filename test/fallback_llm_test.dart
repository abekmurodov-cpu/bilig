import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/llm/fallback_llm.dart';
import 'package:knowledge/src/llm/llm_provider.dart';

import 'quiz_prep_test.dart' show FakeLlm;

/// A fake whose category suggestion reports which AI answered.
class NamedLlm extends FakeLlm {
  NamedLlm(this.name);

  final String name;
  int calls = 0;

  @override
  Future<String> suggestCategory(String front, String? back) async {
    calls++;
    if (failWith != null) throw failWith!;
    return name;
  }
}

void main() {
  late DateTime now;
  late NamedLlm main;
  late NamedLlm backup;
  late FallbackLlm llm;

  setUp(() {
    now = DateTime(2026, 11, 11, 12);
    main = NamedLlm('main');
    backup = NamedLlm('backup');
    llm = FallbackLlm(main, backup, clock: () => now);
  });

  test('uses the main AI while it works', () async {
    expect(await llm.suggestCategory('x', null), 'main');
    expect(backup.calls, 0);
  });

  test('switches to the backup on a limit, and lets the main AI rest', () async {
    main.failWith = const LlmException(LlmErrorKind.rateLimited, 'slow',
        retryAfter: Duration(seconds: 40));
    expect(await llm.suggestCategory('x', null), 'backup');
    expect(llm.usingBackup, isTrue);

    // While resting, the main AI isn't asked at all.
    expect(await llm.suggestCategory('x', null), 'backup');
    expect(main.calls, 1);

    // After the wait it is tried again.
    main.failWith = null;
    now = now.add(const Duration(seconds: 41));
    expect(await llm.suggestCategory('x', null), 'main');
  });

  test('a garbled reply does not switch', () async {
    main.failWith = const LlmException(LlmErrorKind.badResponse, 'garbled');
    await expectLater(llm.suggestCategory('x', null), throwsA(isA<LlmException>()));
    expect(backup.calls, 0);
  });

  test('if the backup fails too, its error is reported', () async {
    main.failWith = const LlmException(LlmErrorKind.quotaExhausted, 'no credit');
    backup.failWith = const LlmException(LlmErrorKind.auth, 'bad key');
    await expectLater(
      llm.suggestCategory('x', null),
      throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.auth)),
    );
  });
}
