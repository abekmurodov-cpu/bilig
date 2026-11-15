import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/knowledge_providers.dart';

/// How many recent categories are offered as one-tap chips.
const int _recentChips = 5;

/// The category of a note: type a letter or two and pick one already in use
/// from the list (it opens on focus, so with a few categories no typing is
/// needed), tap a recent one below, or type a new name.
class CategoryField extends ConsumerStatefulWidget {
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
  ConsumerState<CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends ConsumerState<CategoryField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Categories matching [query]: those starting with it (or with a word
  /// that does) first, then those containing it; all of them when empty.
  List<CategoryInfo> _matches(List<CategoryInfo> all, String query) {
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
    final strings = context.s;
    final theme = Theme.of(context);
    final all = ref.watch(categoryInfoProvider);
    final typed = widget.controller.text.trim();
    final isNew = typed.isNotEmpty &&
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
                optionsBuilder: (value) => _matches(all, value.text),
                onSelected: (c) => _pick(c.name),
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focus,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: widget.labelText ?? strings.categoryOptional,
                    hintText: all.isEmpty ? strings.categoryHint : strings.categoryPickHint,
                    helperText: isNew ? strings.newCategory : null,
                    prefixIcon: const Icon(Icons.folder_outlined),
                    suffixIcon: all.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.chooseCategory,
                            icon: const Icon(Icons.arrow_drop_down),
                            onPressed: () {
                              if (focus.hasFocus) {
                                focus.unfocus();
                              } else {
                                // Empty text lists every category.
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
                              leading: Icon(Icons.folder_outlined,
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
        if (widget.showRecent && all.isNotEmpty && typed.isEmpty) ...[
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
