import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
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
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
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
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "We couldn't load this result. Please try again later.",
                      key: Key('experiment-result-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Aurora.textSecondary),
                    ),
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
        ),
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
    final category = exp.categoryLabel;
    final outcome = exp.outcomeName;

    final message = _message(verdict, reason, category, outcome);
    final showConfirm = verdict == 'improved' && reason == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Aurora.glassFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Aurora.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  key: const Key('experiment-result-message'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Aurora.textPrimary),
                ),
                if (showConfirm) ...[
                  const SizedBox(height: 24),
                  if (confirmed)
                    const Text(
                      'Saved to your trends.',
                      key: Key('experiment-confirm-done'),
                      style: TextStyle(color: Aurora.accentGreen),
                    )
                  else
                    ActionChip(
                      key: const Key('experiment-confirm-chip'),
                      backgroundColor: Aurora.glassFill,
                      side: const BorderSide(color: Aurora.glassBorder),
                      labelStyle: const TextStyle(color: Aurora.textPrimary),
                      avatar: const Icon(
                        Icons.check,
                        size: 18,
                        color: Aurora.accentGreen,
                      ),
                      label: const Text('Confirm this for my trends'),
                      onPressed: confirming ? null : onConfirm,
                    ),
                ],
              ],
            ),
          ),
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
