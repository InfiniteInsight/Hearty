import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers/preferences_provider.dart';

/// A tappable "Talk about my trends" entry shown on the Trends screen ONLY when
/// the monthly trends conversation is enabled in prefs. Routes to
/// /trends-conversation, which loads signals on open (GATE-2 = defer-to-tap).
/// While prefs are unloaded or disabled it renders nothing.
class TrendsConversationEntry extends ConsumerWidget {
  const TrendsConversationEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Don't flash before prefs resolve: default to disabled when unloaded.
    final enabled = ref
            .watch(preferencesProvider)
            .valueOrNull
            ?.trendsConversationEnabled ??
        false;
    if (!enabled) return const SizedBox.shrink();

    return TrendsConversationEntryView(
      key: const Key('trends-convo-entry'),
      onTap: () => context.push('/trends-conversation'),
    );
  }
}

/// Pure presentation — takes [onTap] so it can be widget-tested without a
/// ProviderScope.
class TrendsConversationEntryView extends StatelessWidget {
  final VoidCallback onTap;

  const TrendsConversationEntryView({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.forum_outlined,
                color: scheme.onPrimaryContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Talk about my trends',
                style:
                    TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right,
                color: scheme.onPrimaryContainer, size: 18),
          ],
        ),
      ),
    );
  }
}
