import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../llm/llm_providers.dart';
import '../../practice/practice_models.dart';
import '../../providers/knowledge_providers.dart';
import 'practice_session_screen.dart';

/// Setup screen for a practice run: pick a method and a scope, then start.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  PracticeMethod _method = PracticeMethod.flashcard;
  PracticeScope _scope = PracticeScope.all;
  String? _category;

  void _start() {
    final config = PracticeConfig(
      method: _method,
      scope: _scope,
      category: _category,
    );
    final all = ref.read(notesSortedProvider);
    final due = ref.read(dueItemsProvider);
    final canGenerate = ref.read(llmProvider) != null;
    final queue = config.buildQueue(all: all, due: due, canGenerate: canGenerate);

    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.noMatch)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeSessionScreen(config: config, queue: queue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.s.navPractice)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.s.method, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<PracticeMethod>(
            groupValue: _method,
            onChanged: (v) => setState(() => _method = v!),
            child: Column(
              children: [
                for (final m in PracticeMethod.values.where((m) => !m.isCoding))
                  RadioListTile<PracticeMethod>(
                    value: m,
                    title: Text(context.s.methodLabel(m)),
                    subtitle: Text(context.s.methodBlurb(m)),
                    contentPadding: EdgeInsets.zero,
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.code, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(context.s.codingDrills,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: theme.colorScheme.primary)),
                      const SizedBox(width: 6),
                      Text(context.s.codeNotesOnly,
                          style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                for (final m in PracticeMethod.values.where((m) => m.isCoding))
                  RadioListTile<PracticeMethod>(
                    value: m,
                    title: Text(context.s.methodLabel(m)),
                    subtitle: Text(context.s.methodBlurb(m)),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text(context.s.scope, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<PracticeScope>(
            groupValue: _scope,
            onChanged: (v) => setState(() => _scope = v!),
            child: Column(
              children: [
                for (final s in PracticeScope.values)
                  RadioListTile<PracticeScope>(
                    value: s,
                    title: Text(context.s.scopeLabel(s)),
                    subtitle: Text(context.s.scopeBlurb(s)),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          if (_scope == PracticeScope.category) ...[
            const SizedBox(height: 8),
            if (categories.isEmpty)
              Text(context.s.noCategories)
            else
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: context.s.category,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: (_scope == PracticeScope.category && _category == null)
                ? null
                : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(context.s.startPractice),
          ),
        ],
      ),
    );
  }
}
