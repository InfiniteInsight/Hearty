import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../checkin_question.dart';
import '../providers/checkin_controller.dart';

/// Preview step of the daily check-in: lists every gap (already in backend
/// order A→C→D) with a per-item skip toggle, a "Skip all" action, and a primary
/// "Begin" button. Skips here are preview-only (in-memory) — they do NOT hit
/// the server; only an in-cycle `skipCurrent` on a symptom spends its retry.
class CheckinPreviewView extends ConsumerWidget {
  const CheckinPreviewView({super.key, required this.date});

  /// The reviewed day as `YYYY-MM-DD` — keys the family controller.
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkinControllerProvider(date));
    final controller = ref.read(checkinControllerProvider(date).notifier);
    final count = state.gaps.length;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              '$count ${count == 1 ? 'thing' : 'things'} to review',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: count,
              itemBuilder: (context, i) {
                final gap = state.gaps[i];
                final skipped = state.skipped.contains(i);
                return Card(
                  child: SwitchListTile(
                    key: Key('checkin-preview-toggle-$i'),
                    title: Text(
                      checkinQuestionText(gap),
                      style: skipped
                          ? TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Theme.of(context).disabledColor,
                            )
                          : null,
                    ),
                    // value = "will be reviewed" (i.e. NOT skipped).
                    value: !skipped,
                    onChanged: (_) => controller.toggleSkip(i),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  key: const Key('checkin-begin'),
                  onPressed: controller.begin,
                  child: const Text('Begin'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('checkin-skip-all'),
                  onPressed: controller.skipAll,
                  child: const Text('Skip all'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
