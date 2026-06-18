import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/experiment.dart';

/// Result view for a finished tracked experiment. GATE = defer-to-tap: opened
/// from the end-of-window notification, it evaluates the experiment on first
/// build (no background precompute) and renders the plain-language verdict.
///
/// Only an `improved` verdict (with no blocking `reason`) offers the confirm
/// chip, which writes the result back to trends via the EXISTING
/// [HeartyApiClient.submitSignalVerdict] with verdict `'confirmed'`. Every
/// other verdict is informational only — nothing is written back.
class ExperimentResultScreen extends ConsumerStatefulWidget {
  final String experimentId;

  const ExperimentResultScreen({super.key, required this.experimentId});

  @override
  ConsumerState<ExperimentResultScreen> createState() =>
      _ExperimentResultScreenState();
}

class _ExperimentResultScreenState
    extends ConsumerState<ExperimentResultScreen> {
  late final Future<Experiment> _eval;
  bool _confirmed = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _eval = ref
        .read(heartyApiClientProvider)
        .evaluateExperiment(widget.experimentId);
  }

  Future<void> _confirm(Experiment exp) async {
    if (_confirming || _confirmed) return;
    setState(() => _confirming = true);
    try {
      await ref.read(heartyApiClientProvider).submitSignalVerdict(
            category: exp.category,
            outcomeType: exp.outcomeType,
            outcomeName: exp.outcomeName,
            verdict: 'confirmed',
          );
      if (mounted) setState(() => _confirmed = true);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Experiment result')),
      body: FutureBuilder<Experiment>(
        future: _eval,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                key: Key('experiment-result-loading'),
              ),
            );
          }
          if (snap.hasError || snap.data == null) {
            return const Center(
              child: Text(
                "We couldn't load this result. Please try again later.",
                key: Key('experiment-result-error'),
                textAlign: TextAlign.center,
              ),
            );
          }
          return _ResultBody(
            exp: snap.data!,
            confirmed: _confirmed,
            confirming: _confirming,
            onConfirm: () => _confirm(snap.data!),
          );
        },
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  final Experiment exp;
  final bool confirmed;
  final bool confirming;
  final VoidCallback onConfirm;

  const _ResultBody({
    required this.exp,
    required this.confirmed,
    required this.confirming,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final result = exp.result ?? const <String, dynamic>{};
    final verdict = result['verdict'] as String?;
    final reason = result['reason'] as String?;
    final category = exp.category;
    final outcome = exp.outcomeName;

    final message = _message(verdict, reason, category, outcome);
    final showConfirm = verdict == 'improved' && reason == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            key: const Key('experiment-result-message'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (showConfirm) ...[
            const SizedBox(height: 24),
            if (confirmed)
              const Text(
                'Saved to your trends.',
                key: Key('experiment-confirm-done'),
              )
            else
              ActionChip(
                key: const Key('experiment-confirm-chip'),
                avatar: const Icon(Icons.check, size: 18),
                label: const Text('Confirm this for my trends'),
                onPressed: confirming ? null : onConfirm,
              ),
          ],
        ],
      ),
    );
  }

  String _message(
    String? verdict,
    String? reason,
    String category,
    String outcome,
  ) {
    switch (verdict) {
      case 'improved':
        return 'Cutting $category seems to have helped — $outcome improved.';
      case 'no_change':
        return 'No clear change from cutting $category.';
      case 'worse':
        return 'Cutting $category didn\'t help — $outcome looked a bit worse '
            'during the test.';
      case 'inconclusive':
        if (reason == 'low_adherence') {
          return 'Not enough clean days to tell — $category showed up too '
              'often during the test.';
        }
        if (reason == 'thin_data') {
          return 'Not enough logged data to draw a conclusion.';
        }
        return 'Not enough to draw a conclusion from this test.';
      default:
        return 'Not enough to draw a conclusion from this test.';
    }
  }
}
