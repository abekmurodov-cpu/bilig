import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/data/image_store.dart';
import 'src/data/knowledge_repository.dart';
import 'src/data/secret_store.dart';
import 'src/data/settings_repository.dart';
import 'src/l10n/app_strings.dart';
import 'src/notifications/notification_providers.dart';
import 'src/notifications/notification_service.dart';
import 'src/platform/due_signals.dart';
import 'src/providers/knowledge_providers.dart';
import 'src/providers/settings_providers.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/theme.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await HiveKnowledgeRepository.open();
  final images = await ImageStore.open();
  final settings = await SettingsRepository.open();
  final secrets = await SecretStore.open(settings);
  // People who already have notes don't need the first-run tour.
  if (settings.getString(SettingsRepository.kOnboarded) == null &&
      (await repository.getAll()).isNotEmpty) {
    await settings.setString(SettingsRepository.kOnboarded, 'yes');
  }
  final notifications = NotificationService();
  await notifications.init();

  runApp(
    ProviderScope(
      overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repository),
        imageStoreProvider.overrideWithValue(images),
        settingsRepositoryProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(secrets),
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
      scrollBehavior: const IosScrollBehavior(),
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => _DockIcon(child: child!),
      home: ref.watch(onboardedProvider)
          ? const AppShell()
          : const OnboardingScreen(),
    );
  }
}

/// Keeps the Dock icon (macOS) dark or light with the app's theme, including
/// when the theme follows the system and the system switches.
class _DockIcon extends StatefulWidget {
  const _DockIcon({required this.child});

  final Widget child;

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon> {
  bool? _dark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark != _dark) {
      _dark = dark;
      DueSignals.setDarkIcon(dark);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
