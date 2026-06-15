import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/experiment.dart';

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
    } finally {
      if (mounted) Navigator.of(context).pop();
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
          onPressed: _busy ? null : () => _act((api) => api.abandonExperiment(exp.id)),
          child: const Text('Stop'),
        ),
        TextButton(
          key: const Key('experiment-nudge-restart'),
          onPressed:
              _busy ? null : () => _act((api) => api.restartExperiment(exp.id).then((_) {})),
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
