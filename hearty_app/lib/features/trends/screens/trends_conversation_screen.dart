import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/trends_conversation_provider.dart';

/// Route entry for the monthly trends conversation. Opens the conversation on
/// first frame, then renders by [TrendsConvoPhase]: a spinner while loading,
/// the active chat (assistant reply + text reply box + optional verdict chip),
/// a finite end card, or an error/retry card.
///
/// Text-first: every turn is answerable via the keyboard. Voice is a deferred,
/// device-verified follow-up (see the TODO in [_ActiveView]).
class TrendsConversationScreen extends ConsumerStatefulWidget {
  const TrendsConversationScreen({super.key});

  @override
  ConsumerState<TrendsConversationScreen> createState() =>
      _TrendsConversationScreenState();
}

class _TrendsConversationScreenState
    extends ConsumerState<TrendsConversationScreen> {
  @override
  void initState() {
    super.initState();
    // start() the conversation after first frame so the spinner paints first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(trendsConversationProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trendsConversationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly trends')),
      body: switch (state.phase) {
        TrendsConvoPhase.loading => const Center(
            key: Key('trends-loading'),
            child: CircularProgressIndicator(),
          ),
        TrendsConvoPhase.active => _ActiveView(state: state),
        TrendsConvoPhase.closed => const _EndCard(),
        TrendsConvoPhase.error => const _ErrorCard(),
      },
    );
  }
}

/// The live conversation: the latest assistant reply, a verdict chip when one is
/// pending, a "caught up" note + Done when the assistant is closing, and the
/// text reply box. Inputs are disabled while a request is in flight.
class _ActiveView extends ConsumerStatefulWidget {
  const _ActiveView({required this.state});

  final TrendsConvoState state;

  @override
  ConsumerState<_ActiveView> createState() => _ActiveViewState();
}

class _ActiveViewState extends ConsumerState<_ActiveView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(trendsConversationProvider.notifier).sendUserTurn(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = state.busy;
    final verdict = state.pendingVerdict;
    final experiment = state.pendingExperiment;
    final notifier = ref.read(trendsConversationProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            // Latest assistant reply, shown big.
            Text(
              state.currentReply,
              key: const Key('trends-reply'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            if (verdict != null) ...[
              Card(
                key: const Key('trends-verdict-card'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mark ${verdict.categoryLabel} → ${verdict.outcomeName} '
                        'as ${verdict.verdict}?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            key: const Key('trends-verdict-confirm'),
                            onPressed:
                                busy ? null : () => notifier.confirmVerdict(),
                            child: const Text('Confirm'),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            key: const Key('trends-verdict-dismiss'),
                            onPressed:
                                busy ? null : () => notifier.dismissVerdict(),
                            child: const Text('Not now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            if (experiment != null) ...[
              Card(
                key: const Key('trends-experiment-card'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test this — cut ${experiment.categoryLabel} for 2 weeks?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('trends-experiment-chip'),
                        onPressed:
                            busy ? null : () => notifier.startExperiment(),
                        child: const Text('Start experiment'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            if (state.isClosing) ...[
              Text(
                "We're all caught up.",
                key: const Key('trends-caught-up'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('trends-done'),
                onPressed: busy ? null : () => notifier.close(),
                child: const Text('Done'),
              ),
              const SizedBox(height: 24),
            ],

            // Text reply box. (Voice dictation into sendUserTurn is a deferred,
            // device-verified follow-up.)
            // TODO(trends-voice): device-verified follow-up — a mic button here
            // would dictate into sendUserTurn().
            TextField(
              key: const Key('trends-input'),
              controller: _controller,
              enabled: !busy,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: busy ? null : (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Type your reply…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('trends-send'),
                onPressed: busy ? null : _send,
                child: const Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Finite terminal card shown when the user has ended the conversation.
class _EndCard extends StatelessWidget {
  const _EndCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('trends-closed'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "That's a wrap on this month 🎉",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('trends-close'),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Terminal error card with a retry that re-runs [start].
class _ErrorCard extends ConsumerWidget {
  const _ErrorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      key: const Key('trends-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load your trends conversation.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('trends-retry'),
              onPressed: () =>
                  ref.read(trendsConversationProvider.notifier).start(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
