import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/providers/wellbeing_provider.dart';
import '../../../core/offline/local_wellbeing_dao.dart';
import '../../../core/api/models/wellbeing_period.dart';

class WellbeingLogScreen extends ConsumerStatefulWidget {
  final WellbeingPeriod? initialPeriod;
  final String? entryId;

  const WellbeingLogScreen({
    super.key,
    this.initialPeriod,
    this.entryId,
  });

  @override
  ConsumerState<WellbeingLogScreen> createState() => _WellbeingLogScreenState();
}

class _WellbeingLogScreenState extends ConsumerState<WellbeingLogScreen> {
  late WellbeingPeriod _period;
  int _energy = 3;
  int _mood = 3;
  final _notesController = TextEditingController();
  bool _saving = false;

  bool get _isEditing => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod ?? WellbeingPeriod.inferFromLocalHour();

    if (widget.entryId != null) {
      final entries = ref.read(wellbeingProvider).valueOrNull ?? [];
      final matches = entries.where((e) => e.id == widget.entryId);
      if (matches.isNotEmpty) {
        final entry = matches.first;
        _energy = entry.energy;
        _mood = entry.mood;
        _notesController.text = entry.notes ?? '';
        if (entry.period != null) _period = entry.period!;
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    try {
      if (_isEditing) {
        await ref.read(wellbeingProvider.notifier).updateWellbeing(
              widget.entryId!,
              energy: _energy,
              mood: _mood,
              notes: notes,
              period: _period,
            );
      } else {
        await ref.read(wellbeingProvider.notifier).logWellbeing(
              energy: _energy,
              mood: _mood,
              notes: notes,
              period: _period,
            );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(heartyApiClientProvider).deleteWellbeing(widget.entryId!);
      await ref.read(localWellbeingDaoProvider).deleteByServerId(widget.entryId!);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Wellbeing' : 'Log Wellbeing'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              tooltip: 'Delete',
              onPressed: _deleteEntry,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Period selector
          SegmentedButton<WellbeingPeriod>(
            segments: WellbeingPeriod.values
                .map((p) => ButtonSegment<WellbeingPeriod>(
                      value: p,
                      label: Text(p.label),
                    ))
                .toList(),
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 24),
          _ScaleRow(
            label: 'Energy',
            icon: Icons.bolt,
            value: _energy,
            onChanged: (v) => setState(() => _energy = v),
          ),
          const SizedBox(height: 24),
          _ScaleRow(
            label: 'Mood',
            icon: Icons.sentiment_satisfied,
            value: _mood,
            onChanged: (v) => setState(() => _mood = v),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  const _ScaleRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('$value / 5', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (i) {
            final v = i + 1;
            return GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value == v
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$v',
                  style: TextStyle(
                    color: value == v
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
