import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../providers/checkin_controller.dart';
import '../widgets/checkin_cycle_view.dart';
import '../widgets/checkin_preview_view.dart';

/// Route entry for the daily check-in. Loads the gap queue once on first frame,
/// then renders by [CheckinPhase]: a spinner while loading, the preview list,
/// the one-at-a-time cycle, a finite end card, or an error/retry card.
///
/// Text-first: every gap is answerable via the keyboard. Voice is a deferred,
/// device-verified follow-up (see the TODOs in [CheckinCycleView]).
class DailyCheckinScreen extends ConsumerStatefulWidget {
  const DailyCheckinScreen({super.key, required this.date});

  /// The reviewed day as `YYYY-MM-DD`.
  final String date;

  @override
  ConsumerState<DailyCheckinScreen> createState() => _DailyCheckinScreenState();
}

class _DailyCheckinScreenState extends ConsumerState<DailyCheckinScreen> {
  @override
  void initState() {
    super.initState();
    // load() the queue after first frame so the spinner paints immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(checkinControllerProvider(widget.date).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkinControllerProvider(widget.date));

    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('A few quick questions about your day'),
            titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle ??
                Theme.of(context).textTheme.titleMedium,
          ),
          body: switch (state.phase) {
            CheckinPhase.loading => const Center(
                key: Key('checkin-loading'),
                child: CircularProgressIndicator(),
              ),
            CheckinPhase.preview => CheckinPreviewView(date: widget.date),
            CheckinPhase.cycling => CheckinCycleView(date: widget.date),
            CheckinPhase.done => _EndCard(state: state),
            CheckinPhase.error => _ErrorCard(date: widget.date),
          },
        ),
      ),
    );
  }
}

/// Finite terminal card shown when the cycle is over (or nothing to review /
/// expired window). Branch order matters: expired → empty → everything-done.
class _EndCard extends StatelessWidget {
  const _EndCard({required this.state});

  final CheckinState state;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (state.expired) {
      message = 'This review has expired.';
    } else if (state.gaps.isEmpty) {
      message = "Nothing to review — you're all caught up.";
    } else {
      message = "That's everything for today 🎉";
    }

    return Center(
      key: const Key('checkin-done'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Aurora.glassFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Aurora.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Aurora.textPrimary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('checkin-close'),
                style: FilledButton.styleFrom(
                  backgroundColor: Aurora.accentGreen,
                  foregroundColor: const Color(0xFF052E20),
                ),
                onPressed: () {
                  // Pop back if we can; otherwise fall home (e.g. deep-linked in).
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
      ),
    );
  }
}

/// Terminal error card with a retry that re-runs [CheckinController.load].
class _ErrorCard extends ConsumerWidget {
  const _ErrorCard({required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      key: const Key('checkin-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Aurora.glassFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Aurora.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load your check-in.",
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Aurora.textPrimary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                key: const Key('checkin-retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Aurora.accentGreen,
                  foregroundColor: const Color(0xFF052E20),
                ),
                onPressed: () =>
                    ref.read(checkinControllerProvider(date).notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
