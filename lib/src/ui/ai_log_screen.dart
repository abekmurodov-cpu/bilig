import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../llm/ai_log.dart';

/// Settings → AI activity: the last requests, which AI took each, how long
/// it took and what went wrong, to see at a glance why something AI-made
/// failed.
class AiLogScreen extends ConsumerWidget {
  const AiLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.s;
    final theme = Theme.of(context);
    final entries = ref.watch(aiLogProvider);
    final local = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.aiActivity),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: strings.clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => ref.read(aiLogProvider.notifier).clear(),
            ),
        ],
      ),
      body: entries.isEmpty
          ? Center(child: Text(strings.aiActivityEmpty))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = entries[i];
                final color = e.ok ? const Color(0xFF2E9E4F) : theme.colorScheme.error;
                final time = TimeOfDay.fromDateTime(e.at);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(e.ok ? Icons.check_circle : Icons.error_outline, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(strings.aiTask(e.task), style: theme.textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                '${e.ai} · ${local.formatShortMonthDay(e.at)} '
                                '${local.formatTimeOfDay(time)} · ${(e.millis / 1000).toStringAsFixed(1)} s',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              if (e.error != null) ...[
                                const SizedBox(height: 6),
                                SelectableText(e.error!,
                                    style: theme.textTheme.bodyMedium?.copyWith(color: color)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
