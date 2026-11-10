import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/data/image_store.dart';
import 'src/data/knowledge_repository.dart';
import 'src/data/settings_repository.dart';
import 'src/l10n/app_strings.dart';
import 'src/notifications/notification_providers.dart';
import 'src/notifications/notification_service.dart';
import 'src/providers/knowledge_providers.dart';
import 'src/providers/settings_providers.dart';
import 'src/ui/app_shell.dart';

const _seedColor = Color(0xFF5B6CF0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await HiveKnowledgeRepository.open();
  final images = await ImageStore.open();
  final settings = await SettingsRepository.open();
  final notifications = NotificationService();
  await notifications.init();

  runApp(
    ProviderScope(
      overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repository),
        imageStoreProvider.overrideWithValue(images),
        settingsRepositoryProvider.overrideWithValue(settings),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const BiligApp(),
    ),
  );
}

class BiligApp extends ConsumerWidget {
  const BiligApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    return MaterialApp(
      title: 'Bilig',
      debugShowCheckedModeBanner: false,
      locale: language.locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
