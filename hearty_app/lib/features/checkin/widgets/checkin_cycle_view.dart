import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/checkin_controller.dart';

/// Cycle step of the daily check-in: renders the [CheckinState.current] gap one
/// at a time, branching on its `type`. Text-first — every gap is fully
/// answerable via the keyboard. A voice layer can later drive the same
/// controller methods without touching this widget's structure.
///
/// The per-gap input subtree is keyed by `state.index` so each gap gets a fresh
/// [State] (no text/reveal bleed from the previous gap).
class CheckinCycleView extends ConsumerWidget {
  const CheckinCycleView({super.key, required this.date});

  /// The reviewed day as `YYYY-MM-DD` — keys the family controller.
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkinControllerProvider(date));
    final controller = ref.read(checkinControllerProvider(date).notifier);
    final gap = state.current;
    if (gap == null) return const SizedBox.shrink();

    // 1-based position among all gaps for the progress hint.
    final position = state.index + 1;
    final total = state.gaps.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$position of $total',
            key: const Key('checkin-progress'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            gap.prompt,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          // Fresh State per gap — keying on index resets controllers + reveals.
          _GapInput(
            key: ValueKey('checkin-gap-${state.index}'),
            gap: gap,
            controller: controller,
          ),
        ],
      ),
    );
  }
}

/// Routes to the right input form for the current gap [type] and wires its
/// actions to the matching [CheckinController] method.
class _GapInput extends StatefulWidget {
  const _GapInput({super.key, required this.gap, required this.controller});

  final dynamic gap; // CheckinGap — kept loose to avoid an extra import line.
  final CheckinController controller;

  @override
  State<_GapInput> createState() => _GapInputState();
}

class _GapInputState extends State<_GapInput> {
  final _answerController = TextEditingController();
  final _severityController = TextEditingController();

  /// low_confidence: whether the "No, fix it" correction field is revealed.
  bool _correcting = false;

  bool _busy = false;

  @override
  void dispose() {
    _answerController.dispose();
    _severityController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.gap.type as String) {
      case 'symptom_gap':
        return _buildSymptom();
      case 'low_confidence':
        return _buildLowConfidence();
      case 'missing_chunk':
        return _buildMissingChunk();
      default:
        // Unknown gap type the backend may add — let the user move past it.
        return _buildUnknown();
    }
  }

  // ── symptom_gap ────────────────────────────────────────────────────────────

  Widget _buildSymptom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('checkin-symptom-answer'),
          controller: _answerController,
          decoration: const InputDecoration(
            labelText: 'How did it feel?',
            border: OutlineInputBorder(),
          ),
          maxLines: null,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('checkin-symptom-severity'),
          controller: _severityController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Severity (1–10, optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        // TODO(checkin-voice): device-verified follow-up — a mic button here
        // will dictate the answer + severity, then call resolveSymptom below.
        ElevatedButton(
          key: const Key('checkin-submit'),
          onPressed: _busy
              ? null
              : () => _run(() => widget.controller.resolveSymptom(
                    rawDescription: _answerController.text.trim(),
                    severity: _parseSeverity(),
                  )),
          child: _busy ? _spinner() : const Text('Submit'),
        ),
        _skipButton(),
      ],
    );
  }

  int? _parseSeverity() {
    final raw = _severityController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  // ── low_confidence ──────────────────────────────────────────────────────────

  Widget _buildLowConfidence() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_correcting) ...[
          ElevatedButton(
            key: const Key('checkin-confirm'),
            onPressed:
                _busy ? null : () => _run(() => widget.controller.confirmFood()),
            child: _busy ? _spinner() : const Text('Yes, correct'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('checkin-reveal-fix'),
            onPressed: _busy ? null : () => setState(() => _correcting = true),
            child: const Text('No, fix it'),
          ),
        ] else ...[
          TextField(
            key: const Key('checkin-correct-text'),
            controller: _answerController,
            decoration: const InputDecoration(
              labelText: 'What was it actually?',
              border: OutlineInputBorder(),
            ),
            maxLines: null,
          ),
          const SizedBox(height: 12),
          // TODO(checkin-voice): device-verified follow-up — a mic button here
          // will dictate the correction, then call correctFood below.
          ElevatedButton(
            key: const Key('checkin-submit'),
            onPressed: _busy
                ? null
                : () => _run(() => widget.controller
                    .correctFood(_answerController.text.trim())),
            child: _busy ? _spinner() : const Text('Save correction'),
          ),
        ],
        _skipButton(),
      ],
    );
  }

  // ── missing_chunk ───────────────────────────────────────────────────────────

  Widget _buildMissingChunk() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('checkin-meal-text'),
          controller: _answerController,
          decoration: const InputDecoration(
            labelText: 'What did you have?',
            border: OutlineInputBorder(),
          ),
          maxLines: null,
        ),
        const SizedBox(height: 20),
        // TODO(checkin-voice): device-verified follow-up — a mic button here
        // will dictate the meal, then call logMeal below.
        ElevatedButton(
          key: const Key('checkin-submit'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.controller.logMeal(_answerController.text.trim())),
          child: _busy ? _spinner() : const Text('Log it'),
        ),
        TextButton(
          key: const Key('checkin-skip'),
          onPressed:
              _busy ? null : () => _run(() => widget.controller.skipCurrent()),
          child: const Text("Didn't eat / Skip"),
        ),
      ],
    );
  }

  // ── unknown ─────────────────────────────────────────────────────────────────

  Widget _buildUnknown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          key: const Key('checkin-skip'),
          onPressed:
              _busy ? null : () => _run(() => widget.controller.skipCurrent()),
          child: const Text('Skip'),
        ),
      ],
    );
  }

  // ── shared ──────────────────────────────────────────────────────────────────

  Widget _skipButton() => TextButton(
        key: const Key('checkin-skip'),
        onPressed:
            _busy ? null : () => _run(() => widget.controller.skipCurrent()),
        child: const Text('Skip'),
      );

  Widget _spinner() => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
