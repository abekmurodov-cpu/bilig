import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../llm/llm_providers.dart';
import '../notifications/notification_providers.dart';
import '../providers/knowledge_providers.dart';
import '../providers/settings_providers.dart';
import '../sync/sync_providers.dart';
import '../sync/telegram_sync_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s.navSettings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _ThemeSection(),
          _LanguageSection(),
          if (!kIsWeb) _RemindersSection(),
          _LlmSection(),
          _TelegramSection(),
        ],
      ),
    );
  }
}

/// Reusable section header used across the settings screen.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        child,
        const Divider(height: 24),
      ],
    );
  }
}

class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SettingsSection(
      title: context.s.appearance,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(context.s.themeSystem),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(context.s.themeLight),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(context.s.themeDark),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) =>
              ref.read(themeModeProvider.notifier).set(s.first),
        ),
      ),
    );
  }
}

class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return SettingsSection(
      title: context.s.languageTitle,
      child: RadioGroup<AppLanguage>(
        groupValue: current,
        onChanged: (l) {
          if (l != null) ref.read(languageProvider.notifier).set(l);
        },
        child: Column(
          children: [
            for (final l in AppLanguage.values)
              RadioListTile<AppLanguage>(
                value: l,
                secondary: Text(l.flag, style: const TextStyle(fontSize: 26)),
                title: Text(l.nativeName),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemindersSection extends ConsumerWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminder = ref.watch(reminderProvider);
    final notifier = ref.read(reminderProvider.notifier);
    return SettingsSection(
      title: context.s.reminders,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(context.s.dailyReminder),
            subtitle: Text(context.s.dailyReminderSubtitle),
            value: reminder.enabled,
            onChanged: notifier.setEnabled,
          ),
          ListTile(
            enabled: reminder.enabled,
            leading: const Icon(Icons.schedule),
            title: Text(context.s.reminderTime),
            trailing: Text(reminder.time.format(context)),
            onTap: reminder.enabled
                ? () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: reminder.time,
                    );
                    if (picked != null) {
                      await notifier.setTime(picked.hour, picked.minute);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _LlmSection extends ConsumerStatefulWidget {
  const _LlmSection();

  @override
  ConsumerState<_LlmSection> createState() => _LlmSectionState();
}

class _LlmSectionState extends ConsumerState<_LlmSection> {
  final _keyController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    await ref.read(geminiKeyProvider.notifier).attach(key);
    _keyController.clear();
    if (mounted) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(geminiKeyProvider);
    final attached = key != null && key.isNotEmpty;

    return SettingsSection(
      title: context.s.aiProvider,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: attached
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF2E9E4F)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(context.s.geminiAttached)),
                      TextButton.icon(
                        onPressed: () =>
                            ref.read(geminiKeyProvider.notifier).detach(),
                        icon: const Icon(Icons.link_off),
                        label: Text(context.s.detach),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: context.s.model,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: ref.watch(geminiModelProvider),
                        items: [
                          for (final m in kGeminiModels)
                            DropdownMenuItem(value: m, child: Text(m)),
                        ],
                        onChanged: (m) {
                          if (m != null) {
                            ref.read(geminiModelProvider.notifier).set(m);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.s.geminiBlurb),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: context.s.geminiKey,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _attach,
                      icon: const Icon(Icons.link),
                      label: Text(context.s.attach),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TelegramSection extends ConsumerStatefulWidget {
  const _TelegramSection();

  @override
  ConsumerState<_TelegramSection> createState() => _TelegramSectionState();
}

class _TelegramSectionState extends ConsumerState<_TelegramSection> {
  final _tokenController = TextEditingController();
  final _chatController = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _tokenController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearBusy() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
    });
  }

  Future<void> _attach() async {
    final strings = context.s;
    if (_tokenController.text.trim().isEmpty ||
        _chatController.text.trim().isEmpty) {
      return;
    }
    final token = TelegramSyncService.normalizeToken(_tokenController.text);
    final chatId = TelegramSyncService.normalizeChatId(_chatController.text);
    setState(() {
      _busy = true;
      _status = strings.validatingBot;
    });
    try {
      // Validate the token and chat before persisting.
      final service = TelegramSyncService(botToken: token, chatId: chatId);
      final username = await service.getMe();
      await service.checkChat();
      await ref.read(telegramConfigProvider.notifier).attach(
            TelegramConfig(botToken: token, chatId: chatId, user: username),
          );
      _tokenController.clear();
      _chatController.clear();
      _report(strings.attachedBot(username));
    } catch (e) {
      _report(strings.couldNotAttach(
          e.toString().replaceFirst('Exception: ', '')));
    } finally {
      _clearBusy();
    }
  }

  Future<void> _syncNow() async {
    final strings = context.s;
    final controller = ref.read(syncControllerProvider);
    if (controller == null) return;
    setState(() {
      _busy = true;
      _status = strings.syncing;
    });
    try {
      final summary = await controller.syncNow();
      // Reload the list so merged remote notes appear immediately.
      ref.invalidate(knowledgeListProvider);
      _report(strings.synced(summary.noteCount));
    } catch (e) {
      _report(strings.syncFailed(e));
    } finally {
      _clearBusy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(telegramConfigProvider);
    final attached = config != null;

    return SettingsSection(
      title: context.s.syncTelegram,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: attached
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_done, color: Color(0xFF2E9E4F)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.s.connected(config.user, config.chatId),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _syncNow,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: Text(_status ?? context.s.syncNow),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => ref
                                .read(telegramConfigProvider.notifier)
                                .detach(),
                        icon: const Icon(Icons.link_off),
                        label: Text(context.s.detach),
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.s.telegramBlurb),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      labelText: context.s.botToken,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chatController,
                    decoration: InputDecoration(
                      labelText: context.s.chatId,
                      hintText: context.s.chatIdHint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _attach,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.link),
                      label: Text(_status ?? context.s.attach),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
