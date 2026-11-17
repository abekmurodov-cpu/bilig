import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/knowledge_providers.dart';

/// How many recent categories (or topics) are offered as one-tap chips.
const int _recentChips = 5;

/// The category of a note: type a letter or two and pick one already in use
/// from the list (it opens on focus, so with a few categories no typing is
/// needed), tap a recent one below, or type a new name.
class CategoryField extends ConsumerWidget {
  const CategoryField({
    super.key,
    required this.controller,
    this.labelText,
    this.trailing,
    this.showRecent = true,
  });

  final TextEditingController controller;
  final String? labelText;

  /// Shown after the field (the AI's "suggest a category" button).
  final Widget? trailing;

  /// Whether the recent categories show as chips under the field.
  final bool showRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final all = ref.watch(categoryInfoProvider);
    return PlaceField(
      controller: controller,
      options: all,
      icon: Icons.folder_outlined,
      labelText: labelText ?? strings.categoryOptional,
      hintText: all.isEmpty ? strings.categoryHint : strings.categoryPickHint,
      newLabel: strings.newCategory,
      chooseLabel: strings.chooseCategory,
      trailing: trailing,
      showRecent: showRecent,
    );
  }
}

/// The topic of a note within the category typed in [category]: the same
/// picker, offering that category's topics. Off until there is a category.
class TopicField extends ConsumerStatefulWidget {
  const TopicField({super.key, required this.controller, required this.category});

  final TextEditingController controller;
  final TextEditingController category;

  @override
  ConsumerState<TopicField> createState() => _TopicFieldState();
}

class _TopicFieldState extends ConsumerState<TopicField> {
  @override
  void initState() {
    super.initState();
    widget.category.addListener(_changed);
  }

  @override
  void dispose() {
    widget.category.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final typed = widget.category.text.trim().toLowerCase();
    final topics = ref.watch(topicInfoProvider);
    final options = [
      for (final e in topics.entries)
        if (e.key.toLowerCase() == typed) ...e.value,
    ];
    return PlaceField(
      controller: widget.controller,
      options: options,
      icon: Icons.account_tree_outlined,
      enabled: typed.isNotEmpty,
      labelText: strings.topicOptional,
      hintText: typed.isEmpty
          ? strings.topicNeedsCategory
          : options.isEmpty
              ? strings.topicHint
              : strings.topicPickHint,
      newLabel: strings.newTopic,
      chooseLabel: strings.chooseTopic,
    );
  }
}

/// A text field with a list of names already in use: it opens on focus,
/// narrows as you type, and the most recent show as chips underneath.
class PlaceField extends StatefulWidget {
  const PlaceField({
    super.key,
    required this.controller,
    required this.options,
    required this.icon,
    required this.labelText,
    required this.hintText,
    required this.newLabel,
    required this.chooseLabel,
    this.enabled = true,
    this.trailing,
    this.showRecent = true,
  });

  final TextEditingController controller;

  /// Names in use, most recent first.
  final List<CategoryInfo> options;
  final IconData icon;
  final String labelText;
  final String hintText;

  /// Shown under the field when the typed name isn't one in use.
  final String newLabel;
  final String chooseLabel;
  final bool enabled;
  final Widget? trailing;
  final bool showRecent;

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(PlaceField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Names matching [query]: those starting with it (or with a word that
  /// does) first, then those containing it; all of them when empty.
  List<CategoryInfo> _matches(String query) {
    final all = widget.options;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    if (all.any((c) => c.name.toLowerCase() == q)) return const [];
    int rank(CategoryInfo c) {
      final name = c.name.toLowerCase();
      if (name.startsWith(q)) return 0;
      if (name.split(RegExp(r'[\s/·›\-]+')).any((w) => w.startsWith(q))) return 1;
      if (name.contains(q)) return 2;
      return 3;
    }

    return [for (final c in all) if (rank(c) < 3) c]
      ..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  void _pick(String name) {
    widget.controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = widget.options;
    final typed = widget.controller.text.trim();
    final isNew = widget.enabled &&
        typed.isNotEmpty &&
        !all.any((c) => c.name.toLowerCase() == typed.toLowerCase());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RawAutocomplete<CategoryInfo>(
                textEditingController: widget.controller,
                focusNode: _focus,
                displayStringForOption: (c) => c.name,
                optionsBuilder: (value) =>
                    widget.enabled ? _matches(value.text) : const <CategoryInfo>[],
                onSelected: (c) => _pick(c.name),
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focus,
                  enabled: widget.enabled,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: widget.labelText,
                    hintText: widget.hintText,
                    helperText: isNew ? widget.newLabel : null,
                    prefixIcon: Icon(widget.icon),
                    suffixIcon: all.isEmpty || !widget.enabled
                        ? null
                        : IconButton(
                            tooltip: widget.chooseLabel,
                            icon: const Icon(Icons.arrow_drop_down),
                            onPressed: () {
                              if (focus.hasFocus) {
                                focus.unfocus();
                              } else {
                                // Empty text lists every name.
                                controller.clear();
                                focus.requestFocus();
                              }
                            },
                          ),
                  ),
                ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        children: [
                          for (final c in options)
                            ListTile(
                              dense: true,
                              leading: Icon(widget.icon,
                                  size: 20, color: theme.colorScheme.primary),
                              title: Text(c.name),
                              trailing: Text('${c.count}',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: theme.colorScheme.outline)),
                              onTap: () => onSelected(c),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ?widget.trailing,
          ],
        ),
        if (widget.showRecent && widget.enabled && all.isNotEmpty && typed.isEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in all.take(_recentChips))
                ActionChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(c.name),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _pick(c.name),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
