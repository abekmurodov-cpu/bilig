import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import 'ai_log_screen.dart';
import 'data_section.dart';
import '../llm/ai_services.dart';
import '../llm/llm_provider.dart';
import '../llm/llm_providers.dart';
import '../llm/quiz_prep.dart';
import '../notifications/notification_providers.dart';
import '../notifications/notification_service.dart';
import '../providers/knowledge_providers.dart';
import '../providers/settings_providers.dart';
import '../sync/sync_providers.dart';
import '../sync/telegram_sync_service.dart';
import 'theme.dart';
import 'widgets/ios.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: largeTitleBar(context, title: Text(context.s.navSettings)),
      body: ReadableBuilder(builder: (context, gutter) => ListView(
        padding: EdgeInsets.fromLTRB(0, 4, 0, 24 + MediaQuery.paddingOf(context).bottom) + gutter,
        children: [
          const _ThemeSection(),
          const _LanguageSection(),
          if (NotificationService.supported) const _RemindersSection(),
          const _LlmSection(),
          const DataSection(),
          const _TelegramSection(),
        ],
      )),
    );
  }
}

/// A settings group in the iOS grouped style: a small grey caption above a
/// rounded card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: appFont,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: child,
            ),
          ),
        ],
      ),
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
        child: IosSegmented<ThemeMode>(
          segments: {
            ThemeMode.system: (CupertinoIcons.circle_lefthalf_fill, context.s.themeSystem),
            ThemeMode.light: (CupertinoIcons.sun_max_fill, context.s.themeLight),
            ThemeMode.dark: (CupertinoIcons.moon_fill, context.s.themeDark),
          },
          value: mode,
          onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
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
      // An iOS choice list: a tick by the chosen row.
      child: Column(
        children: [
          for (final l in AppLanguage.values)
            ListTile(
              leading: Text(l.flag, style: const TextStyle(fontSize: 26)),
              title: Text(l.nativeName),
              trailing: l == current
                  ? Icon(CupertinoIcons.checkmark_alt,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () => ref.read(languageProvider.notifier).set(l),
            ),
        ],
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
          IosSwitchTile(
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
                    final picked = await showIosTimePicker(context, reminder.time);
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

class _LlmSection extends ConsumerWidget {
  const _LlmSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(aiConfigProvider);
    return SettingsSection(
      title: context.s.aiProvider,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: config == null
            ? const _AiConnectForm()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AiConnected(config: config),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(context.s.aiActivity),
                    subtitle: Text(context.s.aiActivitySubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiLogScreen())),
                  ),
                ],
              ),
      ),
    );
  }
}

String _serviceName(AiService s) => s.label.split(' (').first;

/// Pick a service, paste a key (the service is recognized from the key where
/// possible), then one "Test & connect" checks it and picks a model.
class _AiConnectForm extends ConsumerStatefulWidget {
  const _AiConnectForm({this.backupFor, this.onCancel});

  /// When set, the form connects a backup for this (main) AI instead.
  final AiService? backupFor;
  final VoidCallback? onCancel;

  @override
  ConsumerState<_AiConnectForm> createState() => _AiConnectFormState();
}

class _AiConnectFormState extends ConsumerState<_AiConnectForm> {
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  final _modelController = TextEditingController();
  // A backup defaults to a free service other than the main one.
  late AiService _service = widget.backupFor == AiService.gemini
      ? AiService.groq
      : AiService.gemini;
  bool _obscure = true;
  bool _busy = false;
  // Shown when no model could be picked automatically.
  bool _askModel = false;
  String? _keyHint;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _onKeyChanged(String value) {
    final guess = guessService(value);
    setState(() {
      if (guess.service != null) {
        _service = guess.service!;
        _keyHint = context.s.detectedService(_serviceName(_service));
      } else if (guess.candidates.length > 1) {
        if (!guess.candidates.contains(_service)) {
          _service = guess.candidates.first;
        }
        _keyHint = context.s.ambiguousKey(
          _serviceName(guess.candidates[0]),
          _serviceName(guess.candidates[1]),
        );
      } else {
        _keyHint = null;
      }
    });
  }

  Future<void> _connect() async {
    final strings = context.s;
    final key = _keyController.text.trim();
    final url = _urlController.text.trim();
    if (_service.needsKey && key.isEmpty) return;
    if (_service == AiService.custom && url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final typedModel = _modelController.text.trim();
    final base = AiConfig(
      service: _service,
      model: typedModel,
      apiKey: key,
      baseUrl: _service == AiService.custom ? url : null,
    );
    // The model list is a convenience: if it fails, the test below reports
    // the real problem.
    var models = const <String>[];
    try {
      models = await createLlm(base).listModels();
    } catch (_) {}

    final model = typedModel.isNotEmpty
        ? typedModel
        : recommendedModel(_service, models);
    if (model == null) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _askModel = true;
        _error = strings.noModelFound;
      });
      return;
    }

    final config = base.withModel(model);
    try {
      await createLlm(config).testConnection();
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = strings.aiFailure(e.kind, e.message);
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
      return;
    }

    final backup = widget.backupFor != null;
    if (backup) {
      await ref.read(backupAiProvider.notifier).attach(config);
    } else {
      await ref.read(aiConfigProvider.notifier).attach(config, models: models);
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          backup
              ? strings.backupLabel(_serviceName(_service), model)
              : '${strings.connectedTo(_serviceName(_service))} · $model',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = _service == AiService.custom;
    final keyUrl = _service.keyUrl;
    final backup = widget.backupFor != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(backup ? context.s.backupBlurb : context.s.aiBlurb),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(
            labelText: context.s.service,
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AiService>(
              isExpanded: true,
              value: _service,
              items: [
                for (final s in AiService.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: s.label),
                          if (s.freeTier)
                            TextSpan(
                              text: '  · ${context.s.freeTier}',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (s) => setState(() {
                      _service = s!;
                      _keyHint = null;
                      _error = null;
                    }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: _onKeyChanged,
          decoration: InputDecoration(
            labelText: custom ? context.s.apiKeyOptional : context.s.apiKey,
            helperText: _keyHint,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (custom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: context.s.serverAddress,
              hintText: 'http://localhost:11434/v1',
            ),
          ),
        ],
        if (custom || _askModel) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.s.modelName,
            ),
          ),
        ],
        if (keyUrl != null)
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(keyUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.s.getKey(_serviceName(_service))),
          )
        else
          const SizedBox(height: 12),
        if (!backup)
          Text(context.s.subscriptionNote, style: theme.textTheme.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null)
              TextButton(
                onPressed: _busy ? null : widget.onCancel,
                child: Text(context.s.cancel),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(),
                    )
                  : const Icon(Icons.link),
              label: Text(_busy ? context.s.testing : context.s.testAndConnect),
            ),
          ],
        ),
      ],
    );
  }
}

/// The optional backup AI under the connected one: add it with the same
/// connect form, or see and remove it.
class _BackupAi extends ConsumerStatefulWidget {
  const _BackupAi({required this.mainService});

  final AiService mainService;

  @override
  ConsumerState<_BackupAi> createState() => _BackupAiState();
}

class _BackupAiState extends ConsumerState<_BackupAi> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final backup = ref.watch(backupAiProvider);
    final theme = Theme.of(context);
    if (backup != null) {
      return Row(
        children: [
          Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.s.backupLabel(_serviceName(backup.service), backup.model),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(backupAiProvider.notifier).detach(),
            child: Text(context.s.remove),
          ),
        ],
      );
    }
    if (_adding) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _AiConnectForm(
          backupFor: widget.mainService,
          onCancel: () => setState(() => _adding = false),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _adding = true),
          icon: const Icon(Icons.add),
          label: Text(context.s.addBackup),
        ),
        Text(context.s.backupBlurb, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// The connected AI: model picker (from the key's own model list), a
/// connection test, and the practice-question status.
class _AiConnected extends ConsumerStatefulWidget {
  const _AiConnected({required this.config});

  final AiConfig config;

  @override
  ConsumerState<_AiConnected> createState() => _AiConnectedState();
}

class _AiConnectedState extends ConsumerState<_AiConnected> {
  static const _otherModel = '\u0000other';
  bool _testing = false;
  bool _loadingModels = false;
  bool? _testOk;
  String? _testMessage;

  Future<void> _test() async {
    final strings = context.s;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    bool ok = false;
    String message;
    try {
      await createLlm(widget.config).testConnection();
      ok = true;
      message = strings.testOk;
    } on LlmException catch (e) {
      message = strings.aiFailure(e.kind, e.message);
    } catch (e) {
      message = '$e';
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testMessage = message;
    });
  }

  Future<void> _refreshModels() async {
    setState(() => _loadingModels = true);
    try {
      final models = await createLlm(widget.config).listModels();
      await ref.read(aiConfigProvider.notifier).setModels(models);
    } catch (e) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = e is LlmException
              ? context.s.aiFailure(e.kind, e.message)
              : '$e';
        });
      }
    }
    if (mounted) setState(() => _loadingModels = false);
  }

  Future<void> _typeModel() async {
    final model = await showIosPrompt(
      context,
      title: context.s.modelName,
      initial: widget.config.model,
      confirm: context.s.save,
      autocorrect: false,
    );
    if (model != null && model.trim().isNotEmpty) {
      await ref.read(aiConfigProvider.notifier).setModel(model.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final theme = Theme.of(context);
    final models = {
      ...ref.read(aiConfigProvider.notifier).models,
      config.model,
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF2E9E4F)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.s.connectedTo(_serviceName(config.service))),
            ),
            TextButton.icon(
              onPressed: () => ref.read(aiConfigProvider.notifier).detach(),
              icon: const Icon(Icons.link_off),
              label: Text(context.s.detach),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: context.s.model,
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: config.model,
                    items: [
                      for (final m in models)
                        DropdownMenuItem(
                          value: m,
                          child: Text(m, overflow: TextOverflow.ellipsis),
                        ),
                      DropdownMenuItem(
                        value: _otherModel,
                        child: Text(
                          context.s.otherModel,
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                    ],
                    onChanged: (m) {
                      if (m == _otherModel) {
                        _typeModel();
                      } else if (m != null) {
                        ref.read(aiConfigProvider.notifier).setModel(m);
                      }
                    },
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: context.s.refreshModels,
              onPressed: _loadingModels ? null : _refreshModels,
              icon: _loadingModels
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CupertinoActivityIndicator(),
                    )
                  : const Icon(Icons.network_check, size: 18),
              label: Text(
                _testing ? context.s.testing : context.s.testConnection,
              ),
            ),
          ],
        ),
        if (_testMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _testMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _testOk == true
                  ? const Color(0xFF2E9E4F)
                  : theme.colorScheme.error,
            ),
          ),
        ],
        const Divider(height: 28),
        _BackupAi(mainService: config.service),
        const Divider(height: 28),
        const _QuizPrepStatus(),
      ],
    );
  }
}

/// How many notes have their AI practice question ready, whether generation
/// is running or paused (and why), with a manual "Prepare now".
class _QuizPrepStatus extends ConsumerWidget {
  const _QuizPrepStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prep = ref.watch(quizPrepProvider);
    final notes = (ref.watch(knowledgeListProvider).asData?.value ?? const [])
        .where((i) => i.front.trim().isNotEmpty)
        .toList();
    final ready = notes.where((i) => !i.needsQuiz).length;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;

    final String? detail;
    if (prep.running) {
      detail = context.s.preparingInBackground;
    } else if (prep.isPaused) {
      final until = prep.pausedUntil;
      detail = until == null
          ? context.s.aiPauseReason(prep.pause!)
          : '${context.s.aiPauseReason(prep.pause!)} '
                '${context.s.resumesAt(TimeOfDay.fromDateTime(until).format(context))}';
    } else {
      detail = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.s.aiQuestionsReady(ready, notes.length)),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (prep.running) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CupertinoActivityIndicator(),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(detail, style: small)),
            ],
          ),
        ],
        if (!prep.running && ready < notes.length)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => ref.read(quizPrepProvider.notifier).retryNow(),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(context.s.prepareNow),
            ),
          ),
      ],
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      await ref
          .read(telegramConfigProvider.notifier)
          .attach(
            TelegramConfig(botToken: token, chatId: chatId, user: username),
          );
      _tokenController.clear();
      _chatController.clear();
      _report(strings.attachedBot(username));
    } catch (e) {
      _report(
        strings.couldNotAttach(e.toString().replaceFirst('Exception: ', '')),
      );
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
                                child: CupertinoActivityIndicator(radius: 8),
                              )
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chatController,
                    decoration: InputDecoration(
                      labelText: context.s.chatId,
                      hintText: context.s.chatIdHint,
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
                              child: CupertinoActivityIndicator(),
                            )
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
