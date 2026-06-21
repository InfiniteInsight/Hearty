import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers/symptoms_provider.dart';

/// Shows the [FeelingFollowUpSheet] as a modal bottom sheet.
///
/// Callers can `await showFeelingFollowUp(context)` and then navigate once the
/// user has saved or skipped. The sheet is dismissible and non-blocking.
Future<void> showFeelingFollowUp(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const FeelingFollowUpSheet(),
    );

/// A reusable, text-first "How are you feeling?" prompt shown after a meal is
/// logged. Records a symptom via the existing
/// [SymptomsNotifier.logSymptom]; no backend changes.
class FeelingFollowUpSheet extends ConsumerStatefulWidget {
  const FeelingFollowUpSheet({super.key});

  @override
  ConsumerState<FeelingFollowUpSheet> createState() =>
      _FeelingFollowUpSheetState();
}

class _FeelingFollowUpSheetState extends ConsumerState<FeelingFollowUpSheet> {
  final _noteController = TextEditingController();

  /// Null until the user picks a severity.
  int? _severity;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final note = _noteController.text.trim();
    final severity = _severity;

    if (note.isNotEmpty || severity != null) {
      await ref
          .read(symptomsProvider.notifier)
          .logSymptom(note, severity: severity);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _skip() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        // Lift content above the keyboard when the note field is focused.
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How are you feeling?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Rate any discomfort 1–10 (optional)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('feeling-note-field'),
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Add a note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _SeveritySelector(
              key: const Key('feeling-severity'),
              value: _severity,
              onChanged: (v) => setState(() => _severity = v),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('feeling-skip'),
                    onPressed: _skip,
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('feeling-save'),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal 1–10 chip row. [value] is null when nothing is selected.
class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 1; i <= 10; i++)
          ChoiceChip(
            label: Text('$i'),
            selected: value == i,
            // Re-tapping the selected chip clears it back to null.
            onSelected: (selected) => onChanged(selected ? i : null),
          ),
      ],
    );
  }
}
