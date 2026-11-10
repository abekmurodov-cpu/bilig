import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/ui/home_screen.dart';

import 'widget_test.dart' show FakeRepository;

Widget app(AppLanguage language) => ProviderScope(
      overrides: [
        knowledgeRepositoryProvider.overrideWithValue(FakeRepository()),
      ],
      child: MaterialApp(
        locale: language.locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeScreen(),
      ),
    );

void main() {
  testWidgets('home screen follows the chosen language', (tester) async {
    for (final (lang, capture) in [
      (AppLanguage.en, 'Capture'),
      (AppLanguage.uz, 'Qo‘shish'),
      (AppLanguage.ru, 'Добавить'),
    ]) {
      await tester.pumpWidget(app(lang));
      await tester.pumpAndSettle();
      expect(find.text(capture), findsOneWidget, reason: lang.name);
    }
  });

  test('Russian plurals', () {
    const ru = AppStrings(AppLanguage.ru);
    expect(ru.readyToChallenge(1), '1 заметка к повторению');
    expect(ru.readyToChallenge(3), '3 заметки к повторению');
    expect(ru.readyToChallenge(11), '11 заметок к повторению');
    expect(ru.readyToChallenge(22), '22 заметки к повторению');
  });
}
