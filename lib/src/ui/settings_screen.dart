import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../llm/ai_services.dart';
import '../llm/llm_provider.dart';
import '../llm/llm_providers.dart';
import '../llm/quiz_prep.dart';
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
            : _AiConnected(config: config),
      ),
    );
  }
}

String _serviceName(AiService s) => s.label.split(' (').first;

/// Pick a service, paste a key (the service is recognized from the key where
/// possible), then one "Test & connect" checks it and picks a model.
class _AiConnectForm extends ConsumerStatefulWidget {
  const _AiConnectForm();

  @override
  ConsumerState<_AiConnectForm> createState() => _AiConnectFormState();
}

class _AiConnectFormState extends ConsumerState<_AiConnectForm> {
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  final _modelController = TextEditingController();
  AiService _service = AiService.gemini;
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
            _serviceName(guess.candidates[0]), _serviceName(guess.candidates[1]));
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

    await ref.read(aiConfigProvider.notifier).attach(config, models: models);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${strings.connectedTo(_serviceName(_service))} · $model'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = _service == AiService.custom;
    final keyUrl = _service.keyUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.s.aiBlurb),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(
            labelText: context.s.service,
            border: const OutlineInputBorder(),
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
                      TextSpan(children: [
                        TextSpan(text: s.label),
                        if (s.freeTier)
                          TextSpan(
                            text: '  · ${context.s.freeTier}',
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                      ]),
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
            border: const OutlineInputBorder(),
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
              border: const OutlineInputBorder(),
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
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (keyUrl != null)
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(keyUrl),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.s.getKey(_serviceName(_service))),
          )
        else
          const SizedBox(height: 12),
        Text(context.s.subscriptionNote, style: theme.textTheme.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
            label: Text(_busy ? context.s.testing : context.s.testAndConnect),
          ),
        ),
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
    final controller = TextEditingController(text: widget.config.model);
    final model = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.s.modelName),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.s.save),
          ),
        ],
      ),
    );
    controller.dispose();
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
    }.toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF2E9E4F)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(context.s.connectedTo(_serviceName(config.service)))),
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
                  border: const OutlineInputBorder(),
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
                        child: Text(context.s.otherModel,
                            style: TextStyle(color: theme.colorScheme.primary)),
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
                      child: CircularProgressIndicator(strokeWidth: 2))
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
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check, size: 18),
              label: Text(_testing ? context.s.testing : context.s.testConnection),
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
        const SizedBox(height: 12),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
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
