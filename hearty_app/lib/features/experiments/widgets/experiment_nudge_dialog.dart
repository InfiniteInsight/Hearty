import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/experiment.dart';
import '../../../core/notifications/notification_service.dart';

/// Active experiments whose adherence is slipping enough that the backend
/// flags [Experiment.nudgeSuggested]. Mirrors `checkinGapsTodayProvider`: an
/// autoDispose [FutureProvider] over an api fetch, surfaced at a home-screen
/// entry. Returns only the experiments that should prompt a nudge.
final experimentNudgesProvider =
    FutureProvider.autoDispose<List<Experiment>>((ref) async {
  final experiments =
      await ref.read(heartyApiClientProvider).fetchActiveExperiments();
  return experiments.where((e) => e.nudgeSuggested).toList();
});

/// Shows the adherence nudge dialog for [experiment]. Each action calls the
/// matching api method then dismisses. Returns once the dialog closes.
Future<void> showExperimentNudgeDialog(
  BuildContext context, {
  required Experiment experiment,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ExperimentNudgeDialog(experiment: experiment),
  );
}

/// The adherence nudge dialog, factored as a standalone [ConsumerWidget] so it
/// can be pumped directly under a [ProviderScope] with a fake api client in
/// tests (mirrors the `CheckinBannerView`/`*View` split). Each action reads
/// [heartyApiClientProvider], fires the matching call, then pops.
class ExperimentNudgeDialog extends ConsumerStatefulWidget {
  final Experiment experiment;

  const ExperimentNudgeDialog({super.key, required this.experiment});

  @override
  ConsumerState<ExperimentNudgeDialog> createState() =>
      _ExperimentNudgeDialogState();
}

class _ExperimentNudgeDialogState extends ConsumerState<ExperimentNudgeDialog> {
  bool _busy = false;

  Future<void> _act(Future<void> Function(HeartyApiClient api) call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call(ref.read(heartyApiClientProvider));
      // Pop only on success — mirrors the result screen's _confirm, which marks
      // success inside the try and only re-enables in finally. A failed action
      // must leave the dialog open rather than dismiss as if it succeeded.
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Action failed — leave the dialog open so the user can retry. (The call
      // site is fire-and-forget, so we must also consume the error here rather
      // than let it escape as an unhandled async error.)
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.experiment;
    return AlertDialog(
      key: const Key('experiment-nudge-dialog'),
      title: Text('Noticed ${exp.category} in a few meals during your '
          'experiment.'),
      content: const Text(
        "Keeping it out gives the test a cleaner read. Want to keep going, "
        'restart the clock, or stop?',
      ),
      actions: [
        TextButton(
          key: const Key('experiment-nudge-stop'),
          onPressed: _busy
              ? null
              : () => _act((api) async {
                    await api.abandonExperiment(exp.id);
                    // Best-effort: cancel the still-pending end-of-window alarm
                    // so a stale tap can't re-evaluate an abandoned experiment.
                    // A plugin-missing failure (e.g. in tests) must not throw.
                    try {
                      await NotificationService
                          .cancelExperimentEndNotification();
                    } catch (_) {/* best-effort */}
                  }),
          child: const Text('Stop'),
        ),
        TextButton(
          key: const Key('experiment-nudge-restart'),
          onPressed: _busy
              ? null
              : () => _act((api) async {
                    final updated = await api.restartExperiment(exp.id);
                    // Reschedule the end notification to the fresh window so the
                    // old (now-stale) alarm doesn't close the new run early.
                    // Best-effort, mirroring startExperiment's guarded schedule.
                    try {
                      await NotificationService.scheduleExperimentEndNotification(
                        experimentId: updated.id,
                        end: DateTime.parse(updated.experimentEnd),
                      );
                    } catch (_) {/* best-effort */}
                  }),
          child: const Text('Restart the clock'),
        ),
        FilledButton(
          key: const Key('experiment-nudge-keep'),
          onPressed: _busy ? null : () => _act((api) => api.ackExperimentNudge(exp.id)),
          child: const Text('Keep going'),
        ),
      ],
    );
  }
}
