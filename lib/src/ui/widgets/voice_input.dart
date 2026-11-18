import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../data/settings_repository.dart';
import '../../l10n/app_strings.dart';
import '../../llm/llm_provider.dart';
import '../../llm/llm_providers.dart';
import '../../providers/settings_providers.dart';
import 'ios.dart';

/// How speech becomes text.
enum VoiceMode {
  /// The device's own speech recognition: free, live, works offline on
  /// most phones; weak or missing for some languages (Uzbek on Apple).
  device,

  /// A recording transcribed by the connected AI (Gemini, OpenAI, Groq).
  ai,
}

/// A mic button for a text field: what the student says is added to
/// [controller].
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.s.speak,
      icon: const Icon(Icons.mic_none),
      onPressed: () async {
        final text = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const VoiceSheet(),
        );
        if (text == null || text.trim().isEmpty) return;
        final current = controller.text.trimRight();
        controller.text = current.isEmpty ? text.trim() : '$current ${text.trim()}';
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      },
    );
  }
}

/// Listens (on the device) or records (for the AI) and returns the text.
class VoiceSheet extends ConsumerStatefulWidget {
  const VoiceSheet({super.key});

  @override
  ConsumerState<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<VoiceSheet> {
  final _speech = SpeechToText();
  AudioRecorder? _recorder;
  final _text = TextEditingController();
  late VoiceMode _mode;
  bool _active = false;
  bool _transcribing = false;
  String? _status;
  List<LocaleName> _locales = const [];
  String? _localeId;
  int _seconds = 0;
  Timer? _timer;

  /// Text from earlier listening runs in this sheet; live results add to it.
  String _before = '';

  static const _maxRecording = Duration(minutes: 2);

  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  bool get _aiAvailable =>
      !kIsWeb && (ref.read(llmProvider)?.canTranscribe ?? false);

  @override
  void initState() {
    super.initState();
    final saved = _settings.getString(SettingsRepository.kVoiceMode);
    _mode = saved == VoiceMode.ai.name && _aiAvailable ? VoiceMode.ai : VoiceMode.device;
    _localeId = _settings.getString(SettingsRepository.kVoiceLocale);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_speech.isListening) _speech.cancel();
    _recorder?.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _setMode(VoiceMode mode) async {
    await _stop(transcribe: false);
    setState(() {
      _mode = mode;
      _status = null;
    });
    await _settings.setString(SettingsRepository.kVoiceMode, mode.name);
  }

  Future<void> _start() async {
    if (_active || _transcribing) return;
    setState(() {
      _status = null;
      _before = _text.text.trim();
    });
    if (_mode == VoiceMode.device) {
      await _startDevice();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startDevice() async {
    final strings = context.s;
    bool ok;
    try {
      ok = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _active = false);
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _active = false;
              _status = e.errorMsg == 'error_no_match' ? strings.nothingHeard : e.errorMsg;
            });
          }
        },
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _status = _aiAvailable
          ? '${strings.speechUnavailable} ${strings.tryAiVoice}'
          : strings.speechUnavailable);
      return;
    }
    if (_locales.isEmpty) {
      final locales = await _speech.locales();
      final lang = ref.read(languageProvider).name;
      locales.sort((a, b) {
        int rank(LocaleName l) {
          final code = l.localeId.substring(0, 2).toLowerCase();
          if (code == lang) return 0;
          return const ['uz', 'ru', 'en'].contains(code) ? 1 : 2;
        }

        final r = rank(a) - rank(b);
        return r != 0 ? r : a.name.compareTo(b.name);
      });
      _locales = locales;
      if (_localeId == null || !locales.any((l) => l.localeId == _localeId)) {
        _localeId = locales.isEmpty ? null : locales.first.localeId;
      }
    }
    setState(() => _active = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenFor: _maxRecording,
        pauseFor: const Duration(seconds: 5),
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        if (!mounted) return;
        final words = r.recognizedWords;
        setState(() => _text.text = _before.isEmpty ? words : '$_before $words');
      },
    );
  }

  Future<void> _startRecording() async {
    final strings = context.s;
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      if (mounted) setState(() => _status = strings.micDenied);
      return;
    }
    final path = '${Directory.systemTemp.path}/bilig_voice.wav';
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _active = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _seconds++);
      if (_seconds >= _maxRecording.inSeconds) _stop();
    });
  }

  Future<void> _stop({bool transcribe = true}) async {
    _timer?.cancel();
    if (_mode == VoiceMode.device) {
      if (_speech.isListening) await _speech.stop();
      if (mounted) setState(() => _active = false);
      return;
    }
    final recorder = _recorder;
    if (recorder == null || !_active) return;
    final path = await recorder.stop();
    if (!mounted) return;
    setState(() => _active = false);
    if (!transcribe || path == null) return;
    await _transcribe(path);
  }

  Future<void> _transcribe(String path) async {
    final strings = context.s;
    final llm = ref.read(llmProvider);
    if (llm == null) return;
    setState(() => _transcribing = true);
    try {
      final bytes = await File(path).readAsBytes();
      final heard = await llm.transcribe(Attachment('audio/wav', bytes));
      if (!mounted) return;
      setState(() {
        if (heard.isEmpty) {
          _status = strings.nothingHeard;
        } else {
          _text.text = _before.isEmpty ? heard : '$_before $heard';
        }
      });
    } on LlmException catch (e) {
      if (mounted) setState(() => _status = strings.aiFailure(e.kind, e.message));
    } catch (e) {
      if (mounted) setState(() => _status = strings.couldNotGenerate(e));
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _setLocale(String? id) async {
    await _stop(transcribe: false);
    setState(() => _localeId = id);
    await _settings.setString(SettingsRepository.kVoiceLocale, id);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final status = _transcribing
        ? strings.writingItDown
        : _active
            ? (_mode == VoiceMode.ai
                ? strings.recordingFor(_seconds)
                : strings.listening)
            : strings.tapToSpeak;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_aiAvailable)
            IosSegmented<VoiceMode>(
              segments: {
                VoiceMode.device: (CupertinoIcons.device_phone_portrait, strings.voiceDevice),
                VoiceMode.ai: (CupertinoIcons.sparkles, strings.voiceAi),
              },
              value: _mode,
              onChanged: _active || _transcribing ? null : _setMode,
            ),
          if (_mode == VoiceMode.device && _locales.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _localeId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.voiceLanguage,
                isDense: true,
              ),
              items: [
                for (final l in _locales)
                  DropdownMenuItem(value: l.localeId, child: Text(l.name)),
              ],
              onChanged: _active ? null : _setLocale,
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: _transcribing
                ? const SizedBox(
                    width: 72, height: 72, child: CupertinoActivityIndicator())
                : IconButton.filled(
                    iconSize: 40,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(80, 80),
                      backgroundColor: _active ? theme.colorScheme.error : null,
                    ),
                    icon: Icon(_active ? Icons.stop : Icons.mic),
                    onPressed: _active ? _stop : _start,
                  ),
          ),
          const SizedBox(height: 8),
          Text(status, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: strings.voiceTextHint,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _text.text.trim().isEmpty || _active || _transcribing
                ? null
                : () => Navigator.of(context).pop(_text.text.trim()),
            icon: const Icon(Icons.check),
            label: Text(strings.insertText),
          ),
        ],
      ),
    );
  }
}
