import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sample_notes.dart';
import '../l10n/app_strings.dart';
import '../providers/knowledge_providers.dart';
import '../providers/settings_providers.dart';
import 'widgets/app_logo.dart';

/// Three swipeable intro screens for a new student, ending with a choice:
/// try Bilig with a small set of sample notes, or start empty.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _busy = false;

  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) => _pages.animateToPage(page,
      duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  Future<void> _finish({required bool withSamples}) async {
    setState(() => _busy = true);
    if (withSamples) {
      await ref
          .read(knowledgeListProvider.notifier)
          .persistAll(sampleNotes(ref.read(languageProvider)));
    }
    await ref.read(onboardedProvider.notifier).finish();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final theme = Theme.of(context);
    final last = _page == _count - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  for (final l in AppLanguage.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        // Flag + code keeps the row narrow enough for phones.
                        tooltip: l.nativeName,
                        label: Text('${l.flag} ${l.name.toUpperCase()}'),
                        selected: ref.watch(languageProvider) == l,
                        onSelected: (_) =>
                            ref.read(languageProvider.notifier).set(l),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const Spacer(),
                  if (!last)
                    TextButton(
                      onPressed: _busy ? null : () => _finish(withSamples: false),
                      child: Text(strings.skip),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _Page(
                    art: const AppLogo(size: 120),
                    title: strings.tour1Title,
                    body: strings.tour1Body,
                  ),
                  _Page(
                    art: _Badge(icon: Icons.auto_awesome, color: theme.colorScheme.tertiary),
                    title: strings.tour2Title,
                    body: strings.tour2Body,
                  ),
                  _Page(
                    art: const _Badge(icon: Icons.park, color: Color(0xFF2E9E4F)),
                    title: strings.tour3Title,
                    body: strings.tour3Body,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: last
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _finish(withSamples: true),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(strings.trySamples),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _finish(withSamples: false),
                          child: Text(strings.startEmpty),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        if (_page > 0)
                          TextButton(
                              onPressed: () => _go(_page - 1),
                              child: Text(strings.previous)),
                        const Spacer(),
                        FilledButton(
                            onPressed: () => _go(_page + 1), child: Text(strings.next)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.art, required this.title, required this.body});

  final Widget art;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              art,
              const SizedBox(height: 32),
              Text(title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Text(body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 60, color: color),
    );
  }
}
