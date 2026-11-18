import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../llm/llm_providers.dart';
import '../../practice/practice_models.dart';
import '../../providers/knowledge_providers.dart';
import 'practice_session_screen.dart';
import '../theme.dart';
import '../widgets/ios.dart';

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
  String? _topic;
  bool _reverse = false;

  void _start() {
    final config = PracticeConfig(
      method: _method,
      scope: _scope,
      category: _category,
      topic: _topic,
      reverse: _reverse && PracticeConfig.canReverse(_method),
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

  /// How many cards [scope] would give with the chosen method.
  int _count(PracticeScope scope, String? category, [String? topic]) => PracticeConfig(
        method: _method,
        scope: scope,
        category: category,
        topic: topic,
        reverse: _reverse && PracticeConfig.canReverse(_method),
      )
          .buildQueue(
            all: ref.watch(notesSortedProvider),
            due: ref.watch(dueItemsProvider),
            canGenerate: ref.watch(llmProvider) != null,
          )
          .length;

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final theme = Theme.of(context);
    final categories = ref.watch(categoryInfoProvider);
    final needsCategory = _scope == PracticeScope.category && _category == null;
    final cards = needsCategory ? 0 : _count(_scope, _category, _topic);
    final topics = ref.watch(topicInfoProvider)[_category] ?? const [];
    Widget heading(String text, {Widget? extra}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Row(
            children: [
              Text(text, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              ?extra,
            ],
          ),
        );
    Widget grid(Iterable<PracticeMethod> methods) => LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 640 ? 3 : 2;
            final width = (box.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in methods)
                  SizedBox(
                    width: width,
                    child: _MethodCard(
                      method: m,
                      selected: _method == m,
                      onTap: () => setState(() => _method = m),
                    ),
                  ),
              ],
            );
          },
        );

    return Scaffold(
      appBar: largeTitleBar(context, title: Text(strings.navPractice)),
      body: ReadableWidth(maxWidth: 900, child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          heading(strings.method),
          grid(PracticeMethod.values.where((m) => !m.isCoding)),
          if (PracticeConfig.canReverse(_method))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Card(
                child: IosSwitchTile(
                  value: _reverse,
                  onChanged: (v) => setState(() => _reverse = v),
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(strings.reverseCards),
                  subtitle: Text(strings.reverseCardsBlurb),
                ),
              ),
            ),
          heading(
            strings.codingDrills,
            extra: Text(strings.codeNotesOnly,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          grid(PracticeMethod.values.where((m) => m.isCoding)),
          heading(strings.scope),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scope in PracticeScope.values)
                ChoiceChip(
                  avatar: Icon(_scopeIcon(scope), size: 18),
                  showCheckmark: false,
                  label: Text(scope == PracticeScope.category
                      ? strings.scopeLabel(scope)
                      : '${strings.scopeLabel(scope)} · ${_count(scope, null)}'),
                  selected: _scope == scope,
                  onSelected: (_) => setState(() => _scope = scope),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(strings.scopeBlurb(_scope),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          if (_scope == PracticeScope.category) ...[
            const SizedBox(height: 12),
            if (categories.isEmpty)
              Text(strings.noCategories)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      showCheckmark: false,
                      label: Text('${c.name} · ${c.count}'),
                      selected: _category == c.name,
                      onSelected: (_) => setState(() {
                        _category = c.name;
                        _topic = null;
                      }),
                    ),
                ],
              ),
            if (topics.isNotEmpty) ...[
              heading(strings.topic),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(strings.allTopics),
                    selected: _topic == null,
                    onSelected: (_) => setState(() => _topic = null),
                  ),
                  for (final t in topics)
                    ChoiceChip(
                      avatar: const Icon(Icons.account_tree_outlined, size: 18),
                      showCheckmark: false,
                      label: Text('${t.name} · ${t.count}'),
                      selected: _topic == t.name,
                      onSelected: (_) => setState(() => _topic = t.name),
                    ),
                ],
              ),
            ],
          ],
        ],
      )),
      bottomNavigationBar: SafeArea(
        child: ReadableWidth(maxWidth: 900, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: cards == 0 ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(needsCategory
                ? strings.pickACategory
                : cards == 0
                    ? strings.noMatch
                    : strings.startCards(cards)),
          ),
        ),)
      ),
    );
  }
}

IconData _scopeIcon(PracticeScope scope) => switch (scope) {
      PracticeScope.all => Icons.all_inclusive,
      PracticeScope.due => Icons.schedule,
      PracticeScope.weakPoints => Icons.trending_down,
      PracticeScope.category => Icons.folder_outlined,
    };

IconData methodIcon(PracticeMethod method) => switch (method) {
      PracticeMethod.flashcard => Icons.style_outlined,
      PracticeMethod.multipleChoice => Icons.checklist,
      PracticeMethod.typeAnswer => Icons.keyboard_outlined,
      PracticeMethod.fillBlank => Icons.space_bar,
      PracticeMethod.codeSnippet => Icons.code,
      PracticeMethod.reorder => Icons.swap_vert,
    };

/// A practice method as a selectable card: icon, name and what it does.
class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.method, required this.selected, required this.onTap});

  final PracticeMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 1.6,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(methodIcon(method),
                        size: 20,
                        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle, size: 20, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(context.s.methodLabel(method),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimaryContainer : null)),
              const SizedBox(height: 2),
              SizedBox(
                height: 34,
                child: Text(context.s.methodBlurb(method),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
